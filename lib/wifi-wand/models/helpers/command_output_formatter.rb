# frozen_string_literal: true

module WifiWand
  module CommandOutputFormatter
    module_function

    def banner_line = @banner_line ||= '-' * 79

    def command_attempt_as_string(command) = "\n\n#{banner_line}\nCommand: #{command}\n"

    def command_result_as_string(output) = "#{output}#{banner_line}\n\n"
  end
end
