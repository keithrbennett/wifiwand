# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Help < Base
      command_metadata(
        short_string: 'h',
        long_string:  'help',
        description:  'print global help or command-specific help',
        usage:        'Usage: wifiwand help [command]'
      )

      binds output: :out_stream
      allow_invocation_options :wifi_interface, :output_format, :utc

      def help_text
        return metadata.usage unless cli

        cli.help_text
      end

      def call(*args)
        validate_max_arguments!(args, 1)

        command_name = args.first
        command = help_command_for(command_name)

        if command&.help_text
          output.puts(command.help_text)
        else
          cli.print_help
        end
      end

      private def help_command_for(command_name)
        return cli.find_command(command_name) if cli.respond_to?(:find_command)

        cli.resolve_command(command_name)
      end
    end
  end
end
