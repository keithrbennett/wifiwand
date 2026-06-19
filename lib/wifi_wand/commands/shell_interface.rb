# frozen_string_literal: true

require_relative 'base'
require_relative '../repl_context'

module WifiWand
  module Commands
    module ShellInterface
      STARTUP_MESSAGE = [
        "For help, type 'h[Enter]' or 'help[Enter]'.",
        '',
        'When in interactive shell mode:',
        '  * remember to quote string literals.',
        '  * for pry commands, use prefix `%`, e.g. `%ls`.',
        '  * Type `qr` to display a Wi-Fi QR code in the shell.',
      ].join("\n")

      # Runs a pry session in the context of a ReplContext object, which exposes
      # all registered commands as explicit named methods.
      def run_shell
        out_stream.puts STARTUP_MESSAGE
        out_stream.puts
        require 'pry'
        require 'amazing_print'

        # Strangely, this is the only thing I have found that successfully suppresses the
        # code context output, which is not useful here. Anyway, this will differentiate
        # a pry command from a DSL command, which _is_ useful here.
        Pry.config.command_prefix = '%'
        Pry.config.print = ->(output, value, _pry) do
          output.puts(value.ai) unless value.equal?(WifiWand::Commands::SILENT_RESULT)
        end
        Pry.config.exception_handler = proc do |output, exception, _pry_|
          output.puts exception.message
        end

        context = WifiWand::ReplContext.new(self)
        catch(:wifiwand_shell_exit) do
          context.pry # rubocop:disable Lint/Debugger
          0
        end
      end

      def quit
        if interactive_mode
          throw(:wifiwand_shell_exit, 0)
        else
          io = @err_stream || $stderr
          io.puts 'This command can only be run in shell mode.'
          1
        end
      end
    end
  end
end
