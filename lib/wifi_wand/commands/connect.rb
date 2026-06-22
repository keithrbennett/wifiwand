# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Connect < Base
      command_metadata(
        short_string: 'co',
        long_string:  'connect',
        description:  'connect to a WiFi network, optionally using an explicit password',
        usage:        'Usage: wifiwand connect <network> [password]'
      )

      binds :model, :interactive_mode, output: :out_stream, err_output: :err_stream
      allow_invocation_options :wifi_interface

      def call(*args)
        validate_max_arguments!(args, 2)

        network, password = args
        raise_missing_argument!('<network>') if missing_argument?(network)

        model.connect(network, password)
        maybe_print_saved_password_message(network)
      end

      private def maybe_print_saved_password_message(network)
        return if interactive_mode
        return unless model.last_connection_used_saved_password?

        message = [
          "Using saved password for '#{network}'.",
          "Use 'forget #{network}' if you need to use a different password.",
        ].join(' ')
        err_output.puts(message)
      end
    end
  end
end
