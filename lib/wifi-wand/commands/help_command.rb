# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class HelpCommand
    SHORT_NAME = 'h'
    LONG_NAME = 'help'
    DESCRIPTION = 'print global help or command-specific help'
    USAGE = 'Usage: wifi-wand help [command]'

    attr_reader :metadata, :cli, :output

    def initialize(metadata: nil, cli: nil, output: $stdout)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @output = output
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli, output: cli.send(:out_stream))
    end

    def help_text
      return metadata.usage unless cli

      cli.help_text
    end

    def call(command_name = nil)
      command = cli.find_bound_command(command_name)

      if command&.help_text
        output.puts(command.help_text)
      else
        cli.print_help
      end
    end
  end
end
