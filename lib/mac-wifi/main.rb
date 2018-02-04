require_relative 'command_line_interface'
require_relative 'operating_systems'


module MacWifi

  require 'json'
  require 'optparse'
  require 'ostruct'
  require 'yaml'

  class Main

    # Parses the command line with Ruby's internal 'optparse'.
    # Looks for "-v" flag to set verbosity to true.
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

          transformers = {
              'i' => ->(object) { object.inspect },
              'j' => ->(object) { JSON.pretty_generate(object) },
              'p' => ->(object) { sio = StringIO.new; sio.puts(object); sio.string },
              'y' => ->(object) { object.to_yaml }
          }

          choice = v[0].downcase

          unless transformers.keys.include?(choice)
            raise %Q{Output format "#{choice}" not in list of available formats} +
                      " (#{transformers.keys.inspect})."
          end

          options.post_processor = transformers[choice]
        end

        parser.on("-h", "--help", "Show help") do |_help_requested|
          ARGV << 'h' # pass on the request to the command processor
        end
      end.parse!
      options
    end


    def call
      operating_systems = OperatingSystems.new
      unless operating_systems.current_id == :mac
        raise "OS not in supported list of #{operating_systems.supported_os_names.inspect}"
      end

      options = parse_command_line

      MacWifi::CommandLineInterface.new(options).call
    end
  end
end