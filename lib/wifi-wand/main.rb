# frozen_string_literal: true

require 'json'
require 'optparse'
require 'ostruct'
require 'stringio'
require 'yaml'
require 'shellwords'

require_relative 'command_line_interface'
require_relative 'operating_systems'
require_relative 'errors'
require_relative 'services/command_executor'


module WifiWand
  class Main
    def initialize(out_stream = $stdout, err_stream = $stderr)
      @out_stream = out_stream
      @err_stream = err_stream
    end

    # Parses the command line with Ruby's internal 'optparse'.
    # optparse removes what it processes from ARGV, which simplifies our command parsing.
    def parse_command_line
      options = OpenStruct.new
      prepend_env_options

      OptionParser.new do |parser|
        parser.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          options.verbose = v
        end

        parser.on('-o', '--output_format FORMAT', 'Format output data') do |v|
          formatters = {
            'i' => lambda(&:inspect),
            'j' => lambda(&:to_json),
            'k' => ->(object) { JSON.pretty_generate(object) },
            'p' => ->(object) {
              sio = StringIO.new
              sio.puts(object)
              sio.string
            },
            'y' => lambda(&:to_yaml)
          }

          choice = v[0].downcase

          unless formatters.keys.include?(choice)
            @err_stream.puts <<~MESSAGE

              Output format "#{choice}" not in list of available formats (#{formatters.keys.join(', ')}).

            MESSAGE
            raise ConfigurationError, "Invalid output format '#{choice}'. Available formats: #{formatters.keys.join(', ')}"
          end

          options.post_processor = formatters[choice]
        end

        parser.on('-p', '--wifi-interface interface', 'WiFi interface name') do |v|
          options.wifi_interface = v
        end

        parser.on('-h', '--help', 'Show help') do |_help_requested|
          options.help_requested = true
          ARGV << 'h' # pass on the request to the command processor
        end
        # Use order! instead of parse! to stop parsing at the first non-option argument (the command name).
        # This allows subcommands (like 'log') to have their own options that aren't parsed by the main parser.
        # .parse! would fail on unrecognized options like --file and --stdout that belong to subcommands.
      end.order!

      if ARGV.first == 'shell'
        options.interactive_mode = true
        ARGV.shift
      end

      options
    end

    def call
      options = parse_command_line
      # Ensure CLI and model share the main's output streams
      options.out_stream = @out_stream
      options.err_stream = @err_stream
      WifiWand::CommandLineInterface.new(options).call
    rescue => e
      # For option parsing errors, we don't have options.verbose yet, so default to false
      verbose = !!options&.verbose
      handle_error(e, verbose)
      # In non-interactive CLI mode, ensure failures return a non-zero exit code
      exit(1) unless options&.interactive_mode
    end

    private

    def prepend_env_options
      raw_options = ENV.fetch('WIFIWAND_OPTS', nil)
      return if raw_options.nil? || raw_options.strip.empty?

      env_args = Shellwords.shellsplit(raw_options)
      return if env_args.empty?

      ARGV.unshift(*env_args)
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid WIFIWAND_OPTS value: #{e.message}"
    end

    def handle_error(error, verbose_mode)
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
