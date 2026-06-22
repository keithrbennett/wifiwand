# frozen_string_literal: true

require 'yaml'
require_relative 'operating_systems'
require_relative 'command_line_options'
require_relative 'errors'
require_relative 'version'
require_relative 'project_url'
require_relative 'timing_constants'
require_relative 'connectivity_states'

# Include extracted modules
require_relative 'commands/help_system'
require_relative 'commands/output_formatter'
require_relative 'commands/registry'
require_relative 'commands/output_support'
require_relative 'commands/shell_interface'

module WifiWand
  class CommandLineInterface
    include Commands::HelpSystem
    include Commands::OutputFormatter
    include Commands::Registry
    include Commands::ShellInterface

    attr_reader :interactive_mode, :options, :command_options, :err_stream, :in_stream

    SUCCESS_EXIT_CODE = 0
    FAILURE_EXIT_CODE = 1

    def initialize(options, argv: nil)
      @options = options
      parsed_argv = argv || options.argv
      @argv = Array(parsed_argv).dup
      @original_out_stream = options.out_stream
      @err_stream = options.err_stream || $stderr
      @in_stream = options.in_stream || $stdin
      @command_options = options.command_options || {}

      @model_options = {
        verbose:        options.verbose,
        utc:            options.utc,
        wifi_interface: options.wifi_interface,
        out_stream:     out_stream,
        err_stream:     err_stream,
      }

      @interactive_mode = !!options.interactive_mode
    end

    def verbose? = options.verbose

    def model
      @model ||= WifiWand.create_model(@model_options)
    end

    # Dynamic output stream that respects current $stdout (for test silence_output compatibility)
    def out_stream = @original_out_stream || $stdout

    def output_support = @output_support ||= Commands::OutputSupport.new(self)

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
        output_arguments if verbose? && !shell_command?

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

    FORMAT_DISPLAY_NAMES = {
      'a' => 'amazing_print',
      'i' => 'inspect',
      'j' => 'json',
      'J' => 'pretty_json',
      'p' => 'puts',
      'P' => 'pp',
      'y' => 'yaml',
    }.freeze

    private def output_arguments
      err_stream.puts '-' * 79
      err_stream.puts "Run at: #{run_timestamp}"
      err_stream.puts "WIFIWAND_OPTS: #{options.wifi_wand_opts_env.inspect}"
      err_stream.puts "raw_argv: #{options.raw_argv.inspect}"
      err_stream.puts "Command: #{@argv.first}"
      parts = [
        "verbose=#{!!options.verbose}",
        "utc=#{!!options.utc}",
        "wifi_interface=#{options.wifi_interface.inspect}",
      ]
      if options.output_format
        label = FORMAT_DISPLAY_NAMES[options.output_format] || options.output_format.inspect
        parts << "output_format=#{label}"
      else
        parts << 'output_format=nil'
      end
      err_stream.puts "Options: #{parts.join(' ')}"
      err_stream.puts '-' * 79
    end

    private def run_timestamp
      options.utc ? Time.now.utc : Time.now
    end

    private def shell_command?
      find_command(@argv.first).is_a?(Commands::Shell)
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
