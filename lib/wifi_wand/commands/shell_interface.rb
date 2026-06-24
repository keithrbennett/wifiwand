# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    module ShellInterface
      STARTUP_MESSAGE = [
        "For help, type 'h[Enter]' or 'help[Enter]'.",
        "To exit the shell, type 'q', 'x', 'exit', or 'quit', or press Ctrl-D.",
        '',
        'When in interactive shell mode:',
        '  * remember to quote string literals.',
        '  * for pry commands, use prefix `%`, e.g. `%ls`.',
        '  * Type `qr` to display a Wi-Fi QR code in the shell.',
      ].join("\n")

      # Runs a pry session in the context of this object.
      # Commands and options specified on the command line can also be specified in the shell.
      def run_shell
        out_stream.puts STARTUP_MESSAGE
        out_stream.puts
        require 'pry'
        require 'amazing_print'

        # Enable the line below if you have any problems with pry configuration being loaded
        # that is messing up this runtime use of pry:
        # Pry.config.should_load_rc = false

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

        catch(:wifiwand_shell_exit) do
          binding.pry # rubocop:disable Lint/Debugger
          0
        end
      end

      # For use by the shell when the user types the DSL commands
      def method_missing(method_name, *method_args)
        attempt_command_action(method_name.to_s, *method_args) do
          raise NoMethodError, <<~MESSAGE
            "#{method_name}" is not a valid command or option.
            If you intended it as an argument to a command, it may be invalid or need quotes.
            MESSAGE
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        !!find_command_action(method_name.to_s) || super
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
