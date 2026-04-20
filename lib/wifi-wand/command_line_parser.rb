# frozen_string_literal: true

require 'json'
require 'optparse'
require 'ostruct'
require 'shellwords'
require 'stringio'
require 'yaml'

require_relative 'errors'

module WifiWand
  class CommandLineParser
    FORMATTERS = {
      'i' => ->(object) { object.inspect },
      'j' => ->(object) { object.to_json },
      'k' => ->(object) { JSON.pretty_generate(object) },
      'p' => ->(object) do
        sio = StringIO.new
        sio.puts(object)
        sio.string
      end,
      'y' => ->(object) { object.to_yaml },
    }.freeze

    def initialize(argv, env, err_stream)
      @argv = argv
      @env = env
      @err_stream = err_stream
    end

    def parse
      args = Array(@argv).dup
      options = OpenStruct.new
      help_requested = false
      prepend_env_options(args)

      OptionParser.new do |parser|
        parser.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          options.verbose = v
        end

        parser.on('-o', '--output_format FORMAT', 'Format output data') do |v|
          choice = v[0].downcase

          unless FORMATTERS.key?(choice)
            @err_stream.puts <<~MESSAGE

              Output format "#{choice}" not in list of available formats (#{FORMATTERS.keys.join(', ')}).

            MESSAGE
            raise ConfigurationError,
              "Invalid output format '#{choice}'. Available formats: #{FORMATTERS.keys.join(', ')}"
          end

          options.post_processor = FORMATTERS[choice]
        end

        parser.on('-p', '--wifi-interface interface', 'WiFi interface name') do |v|
          options.wifi_interface = v
        end

        parser.on('-h', '--help', 'Show help') do
          help_requested = true
        end

        parser.on('-V', '--version', 'Show version') do
          options.version_requested = true
        end
        # Use order! instead of parse! to stop parsing at the first non-option argument (the command name).
        # This allows subcommands (like 'log') to have their own options that aren't parsed by the main parser.
        # .parse! would fail on unrecognized options like --file and --stdout that belong to subcommands.
      end.order!(args)

      if help_requested || help_flag_present?(args)
        options.help_requested = true
        args = ['h']
      elsif args.first == 'shell'
        options.interactive_mode = true
        args.shift
      end

      options.argv = args
      options
    end

    private def prepend_env_options(args)
      raw_options = @env['WIFIWAND_OPTS']
      return if raw_options.nil? || raw_options.strip.empty?

      env_args = Shellwords.shellsplit(raw_options)
      return if env_args.empty?

      args.unshift(*env_args)
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid WIFIWAND_OPTS value: #{e.message}"
    end

    private def help_flag_present?(args)
      args.any? { |arg| ['-h', '--help'].include?(arg) }
    end
  end
end
