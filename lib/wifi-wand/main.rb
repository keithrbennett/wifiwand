require 'json'
require 'optparse'
require 'ostruct'
require 'yaml'

require_relative 'command_line_interface'
require_relative 'operating_systems'


module WifiWand
class Main

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
          message = %Q{Output format "#{choice}" not in list of available formats} <<
              " (#{formatters.keys})."
          puts; puts message; puts
          raise Error.new(message)
        end

        options.post_processor = formatters[choice]
      end

      parser.on("-p", "--wifi-port PORT", "WiFi port name") do |v|
        options.wifi_port = v
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
      WifiWand::CommandLineInterface.new(options).call
    rescue => e
      puts "Error: #{e.backtrace.join("\n")}\n\n#{e.message}"
    end
  end
end
end