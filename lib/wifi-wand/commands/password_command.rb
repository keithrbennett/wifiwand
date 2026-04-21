# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PasswordCommand
    SHORT_NAME = 'pa'
    LONG_NAME = 'password'
    DESCRIPTION = 'show the stored password for a preferred WiFi network'
    USAGE = 'Usage: wifi-wand password <network-name>'

    attr_reader :metadata, :cli, :model

    def initialize(metadata: nil, cli: nil, model: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @model = model
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli, model: cli.model)
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
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
