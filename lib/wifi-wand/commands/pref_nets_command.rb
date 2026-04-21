# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PrefNetsCommand
    SHORT_NAME = 'pr'
    LONG_NAME = 'pref_nets'
    DESCRIPTION = 'show the preferred (saved) WiFi networks'
    USAGE = 'Usage: wifi-wand pref_nets'

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
      networks = model.preferred_networks
      cli.send(:handle_output, networks, -> { cli.send(:format_object, networks) })
    end
  end
end
