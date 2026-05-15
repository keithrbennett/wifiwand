# frozen_string_literal: true

require_relative '../../errors'
require_relative '../../services/command_executor'

module WifiWand
  module Platforms
    module Mac
      class KeychainPasswordReader
        DEFAULT_LOOKUP_TIMEOUT_SECONDS = 5

        # Keychain exit code handlers for password retrieval:
        # 44: item not found, 45: access denied, 128: user cancelled,
        # 51: non-interactive access, 25: invalid search parameters,
        # 1: general error that may contain "could not be found".
        EXIT_CODE_HANDLERS = {
          44  => ->(_network_name, _error) {},
          45  => ->(network_name, _error) { raise KeychainAccessDeniedError, network_name },
          128 => ->(network_name, _error) { raise KeychainAccessCancelledError, network_name },
          51  => ->(network_name, _error) { raise KeychainNonInteractiveError, network_name },
          25  => ->(network_name, _error) {
            raise KeychainError, "Invalid keychain search parameters for network '#{network_name}'"
          },
          1   => ->(network_name, error) {
            if error.text.include?('could not be found')
              nil
            else
              raise KeychainError,
                "Keychain error accessing password for network '#{network_name}': #{error.text.strip}"
            end
          },
        }.freeze

        def initialize(command_runner:)
          @command_runner = command_runner
        end

        def password_for(network_name, timeout_in_secs: DEFAULT_LOOKUP_TIMEOUT_SECONDS)
          @command_runner.call(
            [
              'security',
              'find-generic-password',
              '-D',
              'AirPort network password',
              '-a',
              network_name,
              '-w',
            ],
            raise_on_error:  true,
            timeout_in_secs: timeout_in_secs
          ).stdout.chomp
        rescue WifiWand::CommandExecutor::OsCommandError => e
          handle_keychain_error(network_name, e)
        end

        private def handle_keychain_error(network_name, error)
          handler = EXIT_CODE_HANDLERS[error.exitstatus]

          if handler
            handler.call(network_name, error)
          else
            error_msg = "Unknown keychain error (exit code #{error.exitstatus}) " \
              "accessing password for network '#{network_name}'"
            error_msg += ": #{error.text.strip}" unless error.text.empty?
            raise KeychainError, error_msg
          end
        end
      end
    end
  end
end
