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
      # Parse only the leading global options. Once the first positional token
      # appears, the remaining argv belongs to command dispatch and is left
      # untouched here.
      args = Array(@argv).dup
      options = OpenStruct.new
      help_requested = false
      prepend_env_options(args)

      OptionParser.new do |parser|
        parser.on('-v', '--[no-]verbose', 'Run verbosely') do |value|
          options.verbose = value
        end

        parser.on('-o', '--output_format FORMAT', 'Format output data') do |value|
          options.post_processor = formatter_for(value)
        end

        parser.on('-p', '--wifi-interface INTERFACE', 'WiFi interface name') do |value|
          options.wifi_interface = value
        end

        parser.on('-h', '--help', 'Show help') do
          help_requested = true
        end

        parser.on('-V', '--version', 'Show version') do
          options.version_requested = true
        end
      end.order!(args)

      # Help and version are handled as dedicated top-level flags.
      if help_requested
        options.help_requested = true
        options.argv = ['h']
      elsif args.first == 'shell'
        options.interactive_mode = true
        options.argv = args.drop(1)
      else
        options.argv = args
      end

      options
    end

    private def formatter_for(raw_value)
      choice = raw_value.to_s[0]&.downcase

      unless FORMATTERS.key?(choice)
        @err_stream.puts <<~MESSAGE

          Output format "#{choice}" not in list of available formats (#{FORMATTERS.keys.join(', ')}).

        MESSAGE
        raise ConfigurationError,
          "Invalid output format '#{choice}'. Available formats: #{FORMATTERS.keys.join(', ')}"
      end

      FORMATTERS[choice]
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
  end
end
