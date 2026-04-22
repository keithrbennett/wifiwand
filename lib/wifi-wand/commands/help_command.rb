# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class HelpCommand < Command
    command_metadata(
      short_string: 'h',
      long_string:  'help',
      description:  'print global help or command-specific help',
      usage:        'Usage: wifi-wand help [command]'
    )

    binds :cli, output: :out_stream

    def help_text
      return metadata.usage unless cli

      cli.help_text
    end

    def call(command_name = nil)
      command = cli.resolve_command(command_name)

      if command&.help_text
        output.puts(command.help_text)
      else
        cli.print_help
      end
    end
  end
end
