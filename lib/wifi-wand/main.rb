# frozen_string_literal: true

require 'optparse'
require 'yaml'

require_relative 'command_line_interface'
require_relative 'command_line_parser'
require_relative 'operating_systems'
require_relative 'errors'
require_relative 'services/command_executor'
require_relative 'version'


module WifiWand
  class Main
    SUCCESS_EXIT_CODE = 0
    FAILURE_EXIT_CODE = 1

    def initialize(out_stream = $stdout, err_stream = $stderr, argv: ARGV, env: ENV, in_stream: $stdin)
      @out_stream = out_stream
      @err_stream = err_stream
      @in_stream = in_stream
      @argv = argv
      @env = env
    end

    def call(argv = @argv)
      options = CommandLineParser.new(argv, @env, @err_stream).parse
      if options.version_requested
        @out_stream.puts(WifiWand::VERSION)
        return SUCCESS_EXIT_CODE
      end
      # Ensure CLI and model share the main's output streams
      options.out_stream = @out_stream
      options.err_stream = @err_stream
      options.in_stream = @in_stream
      WifiWand::CommandLineInterface.new(options, argv: options.argv).call
    rescue => e
      # For option parsing errors, we don't have options.verbose yet, so default to false
      verbose = !!options&.verbose
      handle_error(e, verbose)
      FAILURE_EXIT_CODE
    end

    private def handle_error(error, verbose_mode)
      case error
      when OptionParser::InvalidOption
        # Clean error message for invalid command line options
        @err_stream.puts <<~MESSAGE

          Error: #{error.message}

          Use -h or --help to see available options.
        MESSAGE
      when WifiWand::CommandExecutor::OsCommandError
        # Show the helpful command error message and details but not the stack trace
        @err_stream.puts <<~MESSAGE

          Error: #{error.text}
          Command failed: #{error.command}
          Exit code: #{error.exitstatus}
        MESSAGE
      when WifiWand::Error
        # Custom WiFi-related errors already have user-friendly messages
        @err_stream.puts "Error: #{error.message}"
      else
        # Unknown errors - show message but not stack trace unless verbose
        message = if verbose_mode
          <<~MESSAGE
            Error: #{error.message}

            Stack trace:
            #{error.backtrace.join("\n")}
          MESSAGE
        else
          "Error: #{error.message}"
        end
        @err_stream.puts message
      end
    end
  end
end
