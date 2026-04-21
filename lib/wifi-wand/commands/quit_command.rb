# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class QuitCommand
    SHORT_NAME = 'q'
    LONG_NAME = 'quit'
    DESCRIPTION = 'exit this program in interactive shell mode'
    USAGE = 'Usage: wifi-wand quit'
    EXTRA_ALIASES = %w[x xit].freeze

    attr_reader :metadata, :cli

    def initialize(metadata: nil, cli: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
    end

    def aliases
      metadata.aliases + EXTRA_ALIASES
    end

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli)
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}

        Also available as: x, xit
      HELP
    end

    def call
      cli.quit
    end
  end
end
