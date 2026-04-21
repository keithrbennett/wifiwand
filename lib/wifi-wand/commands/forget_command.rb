# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ForgetCommand
    SHORT_NAME = 'f'
    LONG_NAME = 'forget'
    DESCRIPTION = 'remove one or more preferred (saved) WiFi networks'
    USAGE = 'Usage: wifi-wand forget <name1> [name2 ...]'

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

    def call(*options)
      removed_networks = model.remove_preferred_networks(*options)
      cli.send(:handle_output, removed_networks, -> { "Removed networks: #{removed_networks.inspect}" })
    end
  end
end
