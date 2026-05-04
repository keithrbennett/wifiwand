# frozen_string_literal: true

require 'yaml'
require 'awesome_print'
require_relative 'operating_systems'
require_relative 'command_line_options'
require_relative 'errors'
require_relative 'version'
require_relative 'project_url'
require_relative 'timing_constants'
require_relative 'connectivity_states'

# Include extracted modules
require_relative 'command_line_interface/help_system'
require_relative 'command_line_interface/output_formatter'
require_relative 'command_line_interface/command_registry'
require_relative 'command_line_interface/command_output_support'
require_relative 'command_line_interface/shell_interface'

module WifiWand
  class CommandLineInterface
    include HelpSystem
    include OutputFormatter
    include CommandRegistry
    include ShellInterface

    attr_reader :interactive_mode, :model, :options, :err_stream, :in_stream

    SUCCESS_EXIT_CODE = 0
    FAILURE_EXIT_CODE = 1

    def initialize(options, argv: nil)
      @options = options
      parsed_argv = argv || options.argv
      @argv = Array(parsed_argv).dup
      @original_out_stream = options.out_stream
      @err_stream = options.err_stream || $stderr
      @in_stream = options.in_stream || $stdin

      model_options = {
        verbose:        options.verbose,
        wifi_interface: options.wifi_interface,
        out_stream:     out_stream,
      }

      # Skip model initialization when help was explicitly requested in non-interactive mode,
      # so that `--help` works even on systems without Wi‑Fi hardware or permissions.
      @interactive_mode = !!options.interactive_mode
      help_requested = options.help_requested
      skip_model_init = help_requested && !@interactive_mode

      @model = skip_model_init ? nil : WifiWand.create_model(model_options)
    end

    def verbose? = options.verbose

    # Dynamic output stream that respects current $stdout (for test silence_output compatibility)
    def out_stream = @original_out_stream || $stdout

    def output_support = @output_support ||= CommandOutputSupport.new(self)

    # Asserts that a command has been passed on the command line.
    def validate_command_line(argv = @argv)
      if argv.empty?
        @err_stream.puts "Syntax is: #{File.basename($PROGRAM_NAME)} [options] command [args]. " \
          "#{help_hint}"
        return FAILURE_EXIT_CODE
      end

      SUCCESS_EXIT_CODE
    end

    # Processes the command (ARGV[0]) and any relevant options (ARGV[1..-1]).
    #
    # CAUTION! In interactive mode, any strings entered (e.g. a network name) MUST
    # be in a form that the Ruby interpreter will recognize as a string,
    # i.e. single or double quotes, %q, %Q, etc.
    # Otherwise it will assume it's a method name and pass it to method_missing!
    def process_command_line(argv = @argv)
      attempt_command_action(argv[0], *argv[1..]) do
        raise WifiWand::BadCommandError,
          "Unrecognized command. Command was #{argv.first.inspect} and options were #{argv[1..].inspect}."
      end
    end

    # ===== MAIN ENTRY POINT =====

    def call
      return run_shell if interactive_mode

      validation_status = validate_command_line
      return validation_status unless validation_status == SUCCESS_EXIT_CODE

      begin
        # By this time, the Main class has removed the command line options, and all that is left
        # in argv is the command and its options.
        process_command_line
        SUCCESS_EXIT_CODE
      rescue WifiWand::Error => e
        @err_stream.puts(error_message_for(e))
        @err_stream.puts help_hint if append_help_hint?(e)
        FAILURE_EXIT_CODE
      end
    end

    private def append_help_hint?(error)
      error.append_help_hint? && !error.message.include?(help_hint)
    end

    private def error_message_for(error)
      if verbose? && error.respond_to?(:to_h)
        YAML.dump(error.to_h)
      else
        error.message_for_display
      end
    end

    def with_interactive_mode
      previous_mode = @interactive_mode
      @interactive_mode = true
      yield
    ensure
      @interactive_mode = previous_mode
    end
  end
end
