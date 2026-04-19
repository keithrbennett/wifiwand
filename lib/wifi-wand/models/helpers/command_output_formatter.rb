# frozen_string_literal: true

module WifiWand
  module CommandOutputFormatter
    module_function def banner_line = @banner_line ||= '-' * 79

    module_function def command_attempt_as_string(command) = "\n\n#{banner_line}\nCommand: #{command}\n"

    module_function def command_result_as_string(output) = "#{output}#{banner_line}\n\n"
  end
end
