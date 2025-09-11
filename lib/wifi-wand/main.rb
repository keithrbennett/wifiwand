require 'json'
require 'optparse'
require 'ostruct'
require 'stringio'
require 'yaml'

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

    OptionParser.new do |parser|
      parser.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      parser.on("-s", "--shell", "Start interactive shell") do |v|
        options.interactive_mode = true
      end

      parser.on("-o", "--output_format FORMAT", "Format output data") do |v|

        formatters = {
            'i' => ->(object) { object.inspect },
            'j' => ->(object) { object.to_json },
            'k' => ->(object) { JSON.pretty_generate(object) },
            'p' => ->(object) { sio = StringIO.new; sio.puts(object); sio.string },
            'y' => ->(object) { object.to_yaml }
        }

        choice = v[0].downcase

        unless formatters.keys.include?(choice)
          @err_stream.puts <<~MESSAGE

            Output format "#{choice}" not in list of available formats (#{formatters.keys.join(', ')}).

          MESSAGE
          raise ConfigurationError.new("Invalid output format '#{choice}'. Available formats: #{formatters.keys.join(', ')}")
        end

        options.post_processor = formatters[choice]
      end

      parser.on("-p", "--wifi-interface interface", "WiFi interface name") do |v|
        options.wifi_interface = v
      end

      parser.on("-h", "--help", "Show help") do |_help_requested|
        ARGV << 'h' # pass on the request to the command processor
      end
    end.parse!
    options
  end


  def call
    options = parse_command_line

    begin
      # Ensure CLI and model share the main's output streams
      options.out_stream = @out_stream
      options.err_stream = @err_stream
      WifiWand::CommandLineInterface.new(options).call
    rescue => e
      handle_error(e, options.verbose)
    end
  end

  private

  def handle_error(error, verbose_mode)
    case error
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
      if verbose_mode
        message = <<~MESSAGE
          Error: #{error.message}

          Stack trace:
          #{error.backtrace.join("\n")} 
        MESSAGE
      else
        message = "Error: #{error.message}"
      end
      @err_stream.puts message
    end
  end
end
end
