# frozen_string_literal: true

require 'json'
require 'optparse'
require 'ostruct'
require 'shellwords'
require 'stringio'
require 'yaml'

require 'dry/cli'

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

    RESERVED_FLAGS = %w[-h --help -V --version].freeze
    VALUE_OPTIONS = %w[-o --output_format -p --wifi-interface].freeze

    # ============================================================================
    # class OptionCollector: maps parsed global options onto Main's option object
    # ============================================================================
    class OptionCollector
      def initialize(options, err_stream)
        @options = options
        @err_stream = err_stream
      end

      def apply(verbose: nil, output_format: nil, wifi_interface: nil, **)
        @options.verbose = verbose unless verbose.nil?
        @options.post_processor = formatter_for(output_format) if output_format
        @options.wifi_interface = wifi_interface unless wifi_interface.nil?
      end

      # Output formatting is application-specific behavior, so validation and
      # formatter lookup stay in the parser layer instead of the command class.
      private def formatter_for(raw_value)
        choice = raw_value[0].downcase

        unless FORMATTERS.key?(choice)
          @err_stream.puts <<~MESSAGE

            Output format "#{choice}" not in list of available formats (#{FORMATTERS.keys.join(', ')}).

          MESSAGE
          raise ConfigurationError,
            "Invalid output format '#{choice}'. Available formats: #{FORMATTERS.keys.join(', ')}"
        end

        FORMATTERS[choice]
      end
    end
    # ============================================================================
    # end class OptionCollector
    # ============================================================================

    # ============================================================================
    # class GlobalOptionsCommand: dry-cli command for top-level global flags
    # ============================================================================
    class GlobalOptionsCommand < Dry::CLI::Command
      option :verbose, type: :boolean, aliases: ['-v', '--verbose'], desc: 'Run verbosely'
      option :output_format, aliases: ['-o', '--output_format'], desc: 'Format output data'
      option :wifi_interface, aliases: ['-p', '--wifi-interface'], desc: 'WiFi interface name'

      def initialize(collector)
        super()
        @collector = collector
      end

      def call(**)
        @collector.apply(**)
      end
    end
    # ============================================================================
    # end class GlobalOptionsCommand
    # ============================================================================

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
      prepend_env_options(args)

      global_args, remaining_args = split_global_args(args)
      # Help and version are handled as dedicated top-level flags. Ordinary
      # global option parsing goes through dry-cli after those flags are removed.
      options.help_requested = true if reserved_flag_present?(global_args, '-h', '--help')
      options.version_requested = true if reserved_flag_present?(global_args, '-V', '--version')

      parse_global_options(strip_reserved_flags(global_args), options)

      if options.help_requested
        options.argv = ['h']
      elsif remaining_args.first == 'shell'
        options.interactive_mode = true
        options.argv = remaining_args.drop(1)
      else
        options.argv = remaining_args
      end

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

    # Collect only the leading option segment from argv. Anything after the
    # first positional token is passed through unchanged for command handling.
    private def split_global_args(args)
      global_args = []
      index = 0

      while index < args.length
        arg = args[index]
        break unless arg.start_with?('-')

        global_args << arg
        if value_option_requires_next_argument?(arg) && (index + 1) < args.length
          index += 1
          global_args << args[index]
        end
        index += 1
      end

      [global_args, args[index..] || []]
    end

    private def value_option_requires_next_argument?(arg)
      VALUE_OPTIONS.include?(arg)
    end

    private def reserved_flag_present?(args, *flags)
      args.any? { |arg| flags.include?(arg) }
    end

    private def strip_reserved_flags(args)
      args.reject { |arg| RESERVED_FLAGS.include?(arg) }
    end

    # dry-cli handles top-level option parsing. Usage errors are translated
    # into OptionParser-style exceptions so Main can keep one error-formatting
    # path for command-line parsing failures.
    private def parse_global_options(global_args, options)
      collector = OptionCollector.new(options, @err_stream)
      cli = Dry::CLI.new(GlobalOptionsCommand.new(collector))
      cli.call(arguments: global_args, out: StringIO.new, err: @err_stream)
    rescue OptionParser::InvalidOption
      raise
    rescue SystemExit => e
      raise OptionParser::InvalidOption, dry_cli_error_message(e)
    rescue => e
      raise OptionParser::InvalidOption, e.message if dry_cli_usage_error?(e)

      raise
    end

    private def dry_cli_error_message(error)
      return error.message unless @err_stream.respond_to?(:string)

      text = @err_stream.string.to_s.lines.map(&:strip).reject(&:empty?).last
      text.nil? || text.empty? ? error.message : text
    end

    private def dry_cli_usage_error?(error)
      error.class.name.start_with?('Dry::CLI')
    end
  end
end
