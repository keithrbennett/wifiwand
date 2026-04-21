# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class WifiOnCommand
    SHORT_NAME = 'w'
    LONG_NAME = 'wifi_on'
    DESCRIPTION = 'is the WiFi on?'
    USAGE = 'Usage: wifi-wand wifi_on'

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
      on = model.wifi_on?
      cli.send(:handle_output, on, -> { "Wifi on: #{on}" })
    end
  end
end
