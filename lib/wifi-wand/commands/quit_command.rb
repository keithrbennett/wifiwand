# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class QuitCommand < Command
    command_metadata(
      short_string: 'q',
      long_string:  'quit',
      description:  'exit this program in interactive shell mode',
      usage:        'Usage: wifi-wand quit'
    )

    EXTRA_ALIASES = %w[x xit].freeze

    binds :cli

    def aliases
      super + EXTRA_ALIASES
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
