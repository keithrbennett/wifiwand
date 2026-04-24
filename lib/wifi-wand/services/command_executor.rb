# frozen_string_literal: true

require 'open3'
require_relative '../errors'

module WifiWand
  class CommandExecutor
    COMMAND_KILL_WAIT_SECS = 1.0

    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Executes a command using an argument array with no shell parsing.
    # @param command [Array] Command array of arguments
    # @param raise_on_error [Boolean] Whether to raise on non-zero exit
    # @param timeout_in_secs [Numeric, nil] Optional command timeout in seconds
    # @return [OsCommandResult] Structured command result
    def run_command_using_args(command, raise_on_error = true, timeout_in_secs: nil)
      unless command.is_a?(Array)
        raise ArgumentError,
          "run_command_using_args requires an Array; got #{command.class}"
      end

      command_array = command.map { |arg| arg.nil? ? '' : arg.to_s }
      command_display = command_array.join(' ')
      execute_command(command_array, command_display, raise_on_error: raise_on_error,
        timeout_in_secs: timeout_in_secs)
    end

    # Executes a command string through the shell when shell semantics are intended.
    def run_command_using_shell(command, raise_on_error = true, timeout_in_secs: nil)
      unless command.is_a?(String)
        raise ArgumentError,
          "run_command_using_shell requires a String; got #{command.class}"
      end

      execute_command(['sh', '-c', command], command, raise_on_error: raise_on_error,
        timeout_in_secs: timeout_in_secs)
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
        result = run_command_using_args(command)
        stdout_text = result.stdout
        if stop_condition.(stdout_text)
          report_attempt_count.(n + 1)
          return stdout_text
        end
      end

      report_attempt_count.(max_tries)
      nil
    end

    private def execute_command(command_array, command_display, raise_on_error:, timeout_in_secs:)
      if @verbose
        @output.puts command_attempt_as_string(command_display)
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
      Open3.popen3(*command_array, **spawn_options(timeout_in_secs)) do |stdin, stdout, stderr, wait_thr|
        threads = []

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
        #     is available (up to the requested size) - no busy-polling needed.
        #   - read_nonblock in Ruby 4+ internally uses IO::Buffer, which emits
        #     an "experimental" warning we want to avoid.
        # readpartial raises EOFError when the stream closes (i.e., the child
        # process has finished writing), which is used as the loop-exit signal.
        read_stream = ->(stream, type) do
          loop do
            chunk = stream.readpartial(4096)
            mutex.synchronize do
              (type == :stdout ? stdout_chunks : stderr_chunks) << chunk
              combined_chunks << chunk
            end
          end
        rescue EOFError
          nil
        rescue => e
          raise unless e.is_a?(IOError)

          nil
        end

        # Spawn one thread per stream so both are drained in parallel.
        # If we read them sequentially, the child could fill the stderr pipe
        # buffer and deadlock while we were still waiting for stdout to finish
        # (or vice versa). Running concurrently prevents that deadlock.
        threads = [
          Thread.new { read_stream.call(stdout, :stdout) },
          Thread.new { read_stream.call(stderr, :stderr) },
        ]

        wait_result = if timeout_in_secs
          wait_thr.join(timeout_in_secs)
        else
          wait_thr.join
        end

        unless wait_result
          terminate_process(wait_thr)
          raise(CommandTimeoutError.new(command: command_display, timeout_in_secs: timeout_in_secs))
        end

        # Wait for both threads to finish (i.e., both streams are fully read)
        # before asking for the exit status. This guarantees all output has been
        # collected before we return the result.
        threads.each(&:join)

        # wait_thr.value blocks until the child process exits and returns its
        # Process::Status. Calling it after joining the reader threads means the
        # process should already be done by this point in most cases.
        status = wait_thr.value
      ensure
        stdout.close if stdout.respond_to?(:close) && (!stdout.respond_to?(:closed?) || !stdout.closed?)
        stderr.close if stderr.respond_to?(:close) && (!stderr.respond_to?(:closed?) || !stderr.closed?)
        threads&.each(&:join)
      end
    rescue Errno::ENOENT => e
      missing_command = missing_command_name(command_array, e)
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
          @output.puts command_result_as_string("STDOUT:\n#{result.stdout}")
        end
        unless result.stderr.empty?
          @output.puts command_result_as_string("STDERR:\n#{result.stderr}")
        end
        if result.stdout.empty? && result.stderr.empty?
          @output.puts command_result_as_string('')
        end
      end

      if !result.success? && raise_on_error
        raise(OsCommandError.new(result: result))
      end

      result
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

    private def missing_command_name(command, error)
      error_path_present = error.respond_to?(:path) && error.path && !error.path.empty?
      error_path_present ? error.path : Array(command).first.to_s
    end

    private def banner_line = @banner_line ||= '-' * 79

    private def command_attempt_as_string(command) = "\n\n#{banner_line}\nCommand: #{command}\n"

    private def command_result_as_string(output) = "#{output}#{banner_line}\n\n"

    # Timed commands run in their own process group so timeout cleanup can
    # terminate the full process tree rather than only the immediate child.
    private def spawn_options(timeout_in_secs)
      timeout_in_secs ? { pgroup: true } : {}
    end

    # Send signals to the timed command's process group. The direct child may
    # exit before its descendants do, so we must check the group after TERM
    # rather than treating child exit alone as complete cleanup.
    private def terminate_process(wait_thr)
      process_group_id = wait_thr.pid
      Process.kill('TERM', -process_group_id)
      process_exited_within_grace_period?(wait_thr)
      return unless process_group_alive?(process_group_id)

      Process.kill('KILL', -process_group_id)
      process_exited_within_grace_period?(wait_thr)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    # Signal 0 probes whether any member of the process group still exists
    # without sending a terminating signal.
    private def process_group_alive?(process_group_id)
      Process.kill(0, -process_group_id)
      true
    rescue Errno::ESRCH
      false
    end

    private def process_exited_within_grace_period?(wait_thr)
      !!wait_thr.join(COMMAND_KILL_WAIT_SECS)
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

      def initialize(result: nil, exitstatus: nil, command: nil, text: nil)
        @result = result || OsCommandResult.new(
          stdout:          text,
          stderr:          '',
          combined_output: text,
          exitstatus:      exitstatus,
          command:         command,
          duration:        nil
        )

        @exitstatus = @result.exitstatus
        @command = @result.command
        @text = @result.combined_output
      end

      def to_s = "#{self.class.name}: Error code #{exitstatus}, command = #{command}, text = #{text}"

      def to_h = { exitstatus: exitstatus, command: command, text: text }
    end
  end
end
