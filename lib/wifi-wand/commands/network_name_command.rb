# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class NetworkNameCommand
    SHORT_NAME = 'ne'
    LONG_NAME = 'network_name'
    DESCRIPTION = 'show the SSID of the currently connected WiFi network'
    USAGE = 'Usage: wifi-wand network_name'

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

    def call
      name = model.connected_network_name
      cli.send(:handle_output, name, -> { %{Network (SSID) name: "#{name || '[none]'}"} })
    rescue WifiWand::Error => e
      cli.send(:handle_output, nil, -> { e.message })
    end
  end
end
