# frozen_string_literal: true

module WifiWandSpecSupport
  module Fakes
    class FakeCommandExecutor
      attr_accessor :command_available_result, :run_result, :run_shell_result, :try_result
      attr_reader :run_calls, :run_shell_calls, :try_calls, :command_available_calls

      def initialize(default_result:)
        @command_available_result = true
        @run_result = default_result
        @run_shell_result = default_result
        @try_result = nil
        @run_calls = []
        @run_shell_calls = []
        @try_calls = []
        @command_available_calls = []
      end

      def run_command_using_args(command, raise_on_error: true, timeout_in_secs: nil)
        @run_calls << {
          command:         command,
          raise_on_error:  raise_on_error,
          timeout_in_secs: timeout_in_secs,
        }
        evaluate(@run_result, command, raise_on_error: raise_on_error, timeout_in_secs: timeout_in_secs)
      end

      def run_command_using_shell(command, raise_on_error: true, timeout_in_secs: nil)
        @run_shell_calls << {
          command:         command,
          raise_on_error:  raise_on_error,
          timeout_in_secs: timeout_in_secs,
        }
        evaluate(@run_shell_result, command, raise_on_error: raise_on_error, timeout_in_secs: timeout_in_secs)
      end

      def try_os_command_until(command, stop_condition, max_tries)
        @try_calls << { command: command, stop_condition: stop_condition, max_tries: max_tries }
        evaluate(@try_result, command, stop_condition, max_tries)
      end

      def command_available?(command)
        @command_available_calls << command
        evaluate(@command_available_result, command)
      end

      private def evaluate(value, *, **)
        value = value.call(*, **) if value.respond_to?(:call)
        raise value if value.is_a?(Exception)

        value
      end
    end
  end
end
