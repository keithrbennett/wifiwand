# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OnCommand
    SHORT_NAME = 'on'
    LONG_NAME = 'on'
    DESCRIPTION = 'turn WiFi on'
    USAGE = 'Usage: wifi-wand on'

    attr_reader :metadata, :model

    def initialize(metadata: nil, model: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @model = model
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, model: cli.model)
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call
      model.wifi_on
    end
  end
end
