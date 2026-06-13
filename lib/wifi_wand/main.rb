# frozen_string_literal: true

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
    INTERRUPT_EXIT_CODE = 130
    # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
    CLI_BOUNDARY_ERROR = StandardError

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
    rescue Interrupt => e
      handle_interrupt(e, options)
      INTERRUPT_EXIT_CODE
    rescue CLI_BOUNDARY_ERROR => e
      # For option parsing errors, we don't have options.verbose yet, so default to false
      verbose = !!options&.verbose
      handle_error(e, verbose)
      FAILURE_EXIT_CODE
    end

    private def handle_interrupt(error, options)
      message = "Error: Interrupted by Ctrl-C#{interrupt_context(options)}."
      if options&.verbose
        location = interrupt_location(error)
        message = "#{message}\nInterrupted at: #{location}" if location
      end

      @err_stream.puts "\n#{message}"
    end

    private def interrupt_context(options)
      command = interrupt_command(options)

      if command
        " while running command: #{command}"
      else
        ''
      end
    end

    private def interrupt_command(options)
      command = Array(options&.argv).first
      command.to_s.empty? ? nil : command
    end

    private def interrupt_location(error)
      Array(error.backtrace).find { |frame| frame.include?('/lib/wifi_wand/') }
    end

    private def handle_error(error, verbose)
      case error
      when WifiWand::CommandExecutor::OsCommandError
        # Show the helpful command error message and details but not the stack trace
        @err_stream.puts <<~MESSAGE

          Error: #{error.message_for_display}
        MESSAGE
      when WifiWand::Error
        # Custom WiFi-related errors already have user-friendly messages
        @err_stream.puts "Error: #{error.message}"
      else
        # Unknown errors - show message but not stack trace unless verbose
        message = if verbose
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
