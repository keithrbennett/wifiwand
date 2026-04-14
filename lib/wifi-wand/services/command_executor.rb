# frozen_string_literal: true

require 'open3'
require_relative '../models/helpers/command_output_formatter'
require_relative '../errors'

module WifiWand
  class CommandExecutor
    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Executes an OS command using Open3 for security and better error handling.
    # @param command [String, Array] Command string or array of arguments
    # @param raise_on_error [Boolean] Whether to raise on non-zero exit
    # @return [OsCommandResult] Structured command result
    def run_os_command(command, raise_on_error = true)
      # Support both string commands (for backwards compatibility with shell features)
      # and array commands (for secure execution without shell interpretation)
      if command.is_a?(Array)
        command_array = command.map { |arg| arg.nil? ? '' : arg.to_s }
        command_display = command_array.join(' ')
      else
        command_array = ['sh', '-c', command]
        command_display = command
      end

      if @verbose
        @output.puts CommandOutputFormatter.command_attempt_as_string(command_display)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      stdout_chunks = []
      stderr_chunks = []
      combined_chunks = []
      status = nil

      # Open3.popen3 launches the child process and yields three IO objects
      # (stdin, stdout, stderr) plus a thread that will hold the exit status.
      # Using the block form ensures all handles are closed automatically when
      # the block exits, even if an exception is raised.
      Open3.popen3(*command_array) do |stdin, stdout, stderr, wait_thr|
        # We don't send any input to the process, so close stdin immediately.
        # Leaving it open can cause the child to block waiting for input.
        stdin.close

        # A mutex guards the shared chunk arrays below. Two threads write to
        # them concurrently (one per stream), so without synchronization the
        # arrays could be corrupted by interleaved appends.
        mutex = Mutex.new

        # read_stream drains one IO stream into the appropriate chunk arrays.
        # It uses readpartial rather than read_nonblock + IO.select because:
        #   - readpartial blocks until *some* data arrives, then returns whatever
        #     is available (up to the requested size) — no busy-polling needed.
        #   - read_nonblock in Ruby 4+ internally uses IO::Buffer, which emits
        #     an "experimental" warning we want to avoid.
        # readpartial raises EOFError when the stream closes (i.e., the child
        # process has finished writing), which is used as the loop-exit signal.
        read_stream = ->(io, type) do
          loop do
            chunk = io.readpartial(4096)
            mutex.synchronize do
              (type == :stdout ? stdout_chunks : stderr_chunks) << chunk
              combined_chunks << chunk
            end
          rescue EOFError
            break
          end
        end

        # Spawn one thread per stream so both are drained in parallel.
        # If we read them sequentially, the child could fill the stderr pipe
        # buffer and deadlock while we were still waiting for stdout to finish
        # (or vice versa). Running concurrently prevents that deadlock.
        threads = [
          Thread.new { read_stream.call(stdout, :stdout) },
          Thread.new { read_stream.call(stderr, :stderr) },
        ]
        # Wait for both threads to finish (i.e., both streams are fully read)
        # before asking for the exit status. This guarantees all output has been
        # collected before we return the result.
        threads.each(&:join)

        # wait_thr.value blocks until the child process exits and returns its
        # Process::Status. Calling it after joining the reader threads means the
        # process should already be done by this point in most cases.
        status = wait_thr.value
      end
    rescue Errno::ENOENT => e
      missing_command = missing_command_name(command, e)
      raise CommandNotFoundError, missing_command
    else
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      result = OsCommandResult.new(
        stdout:          stdout_chunks.join,
        stderr:          stderr_chunks.join,
        combined_output: combined_chunks.join,
        exitstatus:      status.exitstatus,
        command:         command_display,
        duration:        duration
      )

      status_string = "Exit code: #{result.exitstatus} (#{result.success? ? 'success' : 'error'})"

      if @verbose
        @output.puts "#{status_string}, Duration: #{format('%.4f', duration)} seconds -- #{Time.now.iso8601}"
        unless result.stdout.empty?
          @output.puts CommandOutputFormatter.command_result_as_string("STDOUT:\n#{result.stdout}")
        end
        unless result.stderr.empty?
          @output.puts CommandOutputFormatter.command_result_as_string("STDERR:\n#{result.stderr}")
        end
        if result.stdout.empty? && result.stderr.empty?
          @output.puts CommandOutputFormatter.command_result_as_string('')
        end
      end

      if !result.success? && raise_on_error
        raise OsCommandError, result
      end

      result
    end

    # Tries an OS command until the stop condition is true.
    # @command the command to run in the OS
    # @stop_condition a lambda taking the command's stdout as its sole parameter
    # @return the stdout produced by the command, or nil if max_tries was reached
    def try_os_command_until(command, stop_condition, max_tries = 100)
      report_attempt_count = ->(attempt_count) do
        @output.puts "Command was executed #{attempt_count} time(s)." if @verbose
      end

      max_tries.times do |n|
        result = run_os_command(command)
        stdout_text = result.stdout
        if stop_condition.(stdout_text)
          report_attempt_count.(n + 1)
          return stdout_text
        end
      end

      report_attempt_count.(max_tries)
      nil
    end

    # Checks if a command is available in the system PATH.
    # @param command [String] the command name to search for (e.g., 'git', 'nmcli')
    # @return [Boolean] true if the command exists and is executable
    def command_available?(command)
      ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
        executable = File.join(path, command)
        File.executable?(executable) && !File.directory?(executable)
      end
    end

    private

    def missing_command_name(command, error)
      error_path_present = error.respond_to?(:path) && error.path && !error.path.empty?
      error_path_present ? error.path : Array(command).first.to_s
    end

    class OsCommandResult
      attr_reader :stdout, :stderr, :combined_output, :exitstatus, :command, :duration

      def initialize(stdout:, stderr:, combined_output:, exitstatus:, command:, duration:)
        @stdout = stdout || ''
        @stderr = stderr || ''
        @combined_output = combined_output || ''
        @exitstatus = exitstatus
        @command = command
        @duration = duration
      end

      def success? = exitstatus.to_i.zero?

      def to_s = combined_output

      def to_h
        {
          stdout:          stdout,
          stderr:          stderr,
          combined_output: combined_output,
          exitstatus:      exitstatus,
          command:         command,
          duration:        duration,
        }
      end
    end

    class OsCommandError < WifiWand::Error
      attr_reader :exitstatus, :command, :text, :result

      def initialize(result_or_exitstatus, command = nil, text = nil)
        @result = if result_or_exitstatus.is_a?(OsCommandResult)
          result_or_exitstatus
        else
          OsCommandResult.new(
            stdout:          text,
            stderr:          '',
            combined_output: text,
            exitstatus:      result_or_exitstatus,
            command:         command,
            duration:        nil
          )
        end

        @exitstatus = @result.exitstatus
        @command = @result.command
        @text = @result.combined_output
      end

      def to_s = "#{self.class.name}: Error code #{exitstatus}, command = #{command}, text = #{text}"

      def to_h = { exitstatus: exitstatus, command: command, text: text }
    end
  end
end
