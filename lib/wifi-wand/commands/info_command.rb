# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class InfoCommand
    SHORT_NAME = 'i'
    LONG_NAME = 'info'
    DESCRIPTION = 'a hash of detailed networking information'
    USAGE = 'Usage: wifi-wand info'

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
      info = model.wifi_info
      cli.send(:handle_output, info, -> { cli.send(:format_object, info) })
    end
  end
end
