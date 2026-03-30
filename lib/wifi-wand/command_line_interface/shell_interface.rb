# frozen_string_literal: true

module WifiWand
  class CommandLineInterface
    module ShellInterface

      # Runs a pry session in the context of this object.
      # Commands and options specified on the command line can also be specified in the shell.
      def run_shell
        puts "For help, type 'h[Enter]' or 'help[Enter]'."
        require 'pry'

        # Enable the line below if you have any problems with pry configuration being loaded
        # that is messing up this runtime use of pry:
        # Pry.config.should_load_rc = false

        # Strangely, this is the only thing I have found that successfully suppresses the
        # code context output, which is not useful here. Anyway, this will differentiate
        # a pry command from a DSL command, which _is_ useful here.
        Pry.config.command_prefix = '%'
        Pry.config.print = ->(output, value, _pry) { output.puts(value.awesome_inspect) }
        Pry.config.exception_handler = proc do |output, exception, _pry_|
          output.puts exception.message
        end

        binding.pry
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

      def quit
        if interactive_mode
          exit(0)
        else
          io = @err_stream || $stderr
          io.puts 'This command can only be run in shell mode.'
        end
      end

    end
  end
end
