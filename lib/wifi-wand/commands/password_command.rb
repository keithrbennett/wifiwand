# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PasswordCommand < Command
    SHORT_NAME = 'pa'
    LONG_NAME = 'password'
    DESCRIPTION = 'show the stored password for a preferred WiFi network'
    USAGE = 'Usage: wifi-wand password <network-name>'

    attr_reader :metadata, :cli, :model

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli, model: cli.model)
    end

    def call(network)
      password = model.preferred_network_password(network)
      human_readable_string_producer = -> do
        %(Preferred network "#{network}" ) +
          (password ? %(stored password is "#{password}".) : 'has no stored password.')
      end
      cli.send(:handle_output, password, human_readable_string_producer)
    end
  end
end
