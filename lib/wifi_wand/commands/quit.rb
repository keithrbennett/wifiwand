# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Quit < Base
      command_metadata(
        short_string: 'q',
        long_string:  'quit',
        description:  'exit this program in interactive shell mode',
        usage:        'Usage: wifi-wand quit'
      )

      EXTRA_ALIASES = %w[x xit].freeze

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

      def call(*args)
        validate_max_arguments!(args, 0)

        cli.quit
      end
    end
  end
end
