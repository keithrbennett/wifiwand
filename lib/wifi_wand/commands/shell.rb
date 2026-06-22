# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Shell < Base
      command_metadata(
        short_string: 'sh',
        long_string:  'shell',
        description:  'start interactive shell (interactive pry REPL session)',
        usage:        'Usage: wifiwand shell'
      )

      allow_invocation_options :wifi_interface, :output_format, :utc

      def call(*args)
        validate_startup_options!(args)

        cli.with_interactive_mode do
          cli.run_shell
        end
      end

      private def validate_startup_options!(args)
        validate_max_arguments!(args, 0)

        if cli.options.post_processor && output_format_source != :environment
          raise WifiWand::ConfigurationError,
            'Output formatting is not supported for the shell command.'
        end
      end

      private def output_format_source
        cli.options.invocation_option_sources&.fetch(:output_format, nil)
      end
    end
  end
end
