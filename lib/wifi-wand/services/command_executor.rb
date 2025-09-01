require_relative '../models/helpers/command_output_formatter'

module WifiWand
  class CommandExecutor
    
    def initialize(verbose: false)
      @verbose = verbose
    end

    def run_os_command(command, raise_on_error = true)
      if @verbose
        puts CommandOutputFormatter.command_attempt_as_string(command)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output = `#{command} 2>&1` # join stderr with stdout

      status = Process.last_status
      status_string = "Exit code: #{status.exitstatus} (#{status.success? ? 'success' : 'error'})"

      if @verbose
        puts "#{status_string}, Duration: #{'%.4f' % [Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time]} seconds -- #{Time.now.iso8601}"
        puts CommandOutputFormatter.command_result_as_string(output)
      end

      if $?.exitstatus != 0 && raise_on_error
        raise OsCommandError.new($?.exitstatus, command, output)
      end

      output
    end

    # Tries an OS command until the stop condition is true.
    # @command the command to run in the OS
    # @stop_condition a lambda taking the command's stdout as its sole parameter
    # @return the stdout produced by the command, or nil if max_tries was reached
    def try_os_command_until(command, stop_condition, max_tries = 100)

      report_attempt_count = ->(attempt_count) do
        puts "Command was executed #{attempt_count} time(s)." if @verbose
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

    def command_available_using_which?(command)
      !`which #{command} 2>/dev/null`.empty?
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