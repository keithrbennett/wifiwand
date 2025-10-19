# frozen_string_literal: true

require 'open3'
require_relative '../models/helpers/command_output_formatter'

module WifiWand
  class CommandExecutor

    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Executes an OS command using Open3 for security and better error handling.
    # @param command [String, Array] Command string or array of arguments
    # @param raise_on_error [Boolean] Whether to raise on non-zero exit
    # @return [String] Combined stdout/stderr output
    def run_os_command(command, raise_on_error = true)
      # Support both string commands (for backwards compatibility with shell features)
      # and array commands (for secure execution without shell interpretation)
      command_array = command.is_a?(Array) ? command : ['sh', '-c', command]
      command_display = command.is_a?(Array) ? command.join(' ') : command

      if @verbose
        @output.puts CommandOutputFormatter.command_attempt_as_string(command_display)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Use capture2e to combine stdout and stderr (mimics 2>&1 behavior)
      output, status = Open3.capture2e(*command_array)

      status_string = "Exit code: #{status.exitstatus} (#{status.success? ? 'success' : 'error'})"

      if @verbose
        @output.puts "#{status_string}, Duration: #{'%.4f' % [Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time]} seconds -- #{Time.now.iso8601}"
        @output.puts CommandOutputFormatter.command_result_as_string(output)
      end

      if status.exitstatus != 0 && raise_on_error
        raise OsCommandError.new(status.exitstatus, command_display, output)
      end

      output
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
        stdout_text = run_os_command(command)
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

    class OsCommandError < RuntimeError
      attr_reader :exitstatus, :command, :text

      def initialize(exitstatus, command, text)
        @exitstatus = exitstatus
        @command = command
        @text = text
      end

      def to_s
        "#{self.class.name}: Error code #{exitstatus}, command = #{command}, text = #{text}"
      end

      def to_h
        { exitstatus: exitstatus, command: command, text: text }
      end
    end
  end
end
