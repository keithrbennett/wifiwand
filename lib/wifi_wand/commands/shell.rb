# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Shell < Base
      command_metadata(
        short_string: 'sh',
        long_string:  'shell',
        description:  'start interactive shell (interactive pry REPL session)',
        usage:        'Usage: wifi-wand shell'
      )

      def call(*args)
        validate_startup_options!(args)

        cli.with_interactive_mode do
          cli.run_shell
        end
      end

      private def validate_startup_options!(args)
        validate_max_arguments!(args, 0)

        if cli.options.post_processor
          raise WifiWand::ConfigurationError,
            'Output formatting is not supported for the shell command.'
        end
      end
    end
  end
end
