# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ShellCommand < Command
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
      if args.size.positive?
        raise WifiWand::ConfigurationError,
          "The shell command does not accept arguments. Received: #{args.inspect}"
      elsif cli.options.post_processor
        raise WifiWand::ConfigurationError,
          'Output formatting is not supported for the shell command.'
      end
    end
  end
end
