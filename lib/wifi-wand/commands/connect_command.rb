# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ConnectCommand < Command
    command_metadata(
      short_string: 'co',
      long_string:  'connect',
      description:  'connect to a WiFi network, optionally using an explicit password',
      usage:        'Usage: wifi-wand connect <network> [password]'
    )

    binds :model, :interactive_mode, output: :out_stream

    def call(network, password = nil)
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
      output.puts(message)
    end
  end
end
