# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pp'
require 'shellwords'
require 'stringio'
require 'yaml'

require_relative 'command_line_options'
require_relative 'commands/registry'
require_relative 'errors'
require_relative 'string_predicates'

module WifiWand
  class CommandLineParser
    include Commands::Registry
    include StringPredicates

    FORMATTERS = {
      'a' => ->(object) do
        require 'amazing_print'
        object.ai(plain: false)
      end,
      'i' => ->(object) { object.inspect },
      'j' => ->(object) { object.to_json },
      'J' => ->(object) { JSON.pretty_generate(object) },
      'p' => ->(object) do
        sio = StringIO.new
        sio.puts(object)
        sio.string
      end,
      'P' => ->(object) do
        sio = StringIO.new
        PP.pp(object, sio)
        sio.string
      end,
      'y' => ->(object) { object.to_yaml },
    }.freeze
    FORMAT_LONG_NAMES = {
      'amazing_print' => 'a',
      'inspect'       => 'i',
      'json'          => 'j',
      'pretty_json'   => 'J',
      'puts'          => 'p',
      'pretty_print'  => 'P',
      'yaml'          => 'y',
    }.freeze
    VALUE_TAKING_INVOCATION_OPTIONS = %w[
      -v --verbose -u --utc -o --output-format --output_format -p --wifi-interface
    ].freeze
    INVOCATION_OPTION_ALIASES = {
      help:           %w[-h --help],
      output_format:  %w[-o --output-format --output_format],
      utc:            %w[-u --utc],
      verbose:        %w[-v --verbose],
      version:        %w[-V --version],
      wifi_interface: %w[-p --wifi-interface],
    }.freeze

    def initialize(argv, env, err_stream)
      @argv = argv
      @env = env
      @err_stream = err_stream
    end

    def parse
      raw_cli_args = Array(@argv)
      args = raw_cli_args.dup
      options = CommandLineOptions.new
      specified_invocation_options = []
      command_options = {}
      help_requested = false
      prepend_env_options(args)
      selected_command = selected_command_from(args)
      normalize_command_option_args!(args, selected_command)

      parser = OptionParser.new do |parser|
        parser.on('-v', '--verbose BOOLEAN', TrueClass, 'Run verbosely') do |value|
          specified_invocation_options << :verbose
          options.verbose = value
        end

        parser.on(
          '-u',
          '--utc BOOLEAN',
          TrueClass,
          'Use UTC for timestamps (default: false, for local time)'
        ) do |value|
          specified_invocation_options << :utc
          options.utc = value
        end

        parser.on('-o', '--output-format FORMAT', '--output_format FORMAT', 'Format output data') do |value|
          specified_invocation_options << :output_format
          options.output_format = normalized_format_choice(value)
          options.post_processor = formatter_for(value)
        end

        parser.on('-p', '--wifi-interface INTERFACE', 'WiFi interface name') do |value|
          specified_invocation_options << :wifi_interface
          options.wifi_interface = value
        end

        parser.on('-h', '--help', 'Show help') do
          specified_invocation_options << :help
          help_requested = true
        end

        parser.on('-V', '--version', 'Show version') do
          specified_invocation_options << :version
          options.version_requested = true
        end

        add_command_options(parser, selected_command, command_options)
      end
      parse_options!(parser, args, selected_command)
      options.specified_invocation_options = specified_invocation_options.uniq
      options.invocation_option_sources = invocation_option_sources_for(
        options.specified_invocation_options,
        cli_args: raw_cli_args
      )
      selected_command_argv = command_argv_for(args, selected_command)
      unless help_or_version?(help_requested, options)
        validate_command_options!(selected_command, options, command_options, selected_command_argv)
      end

      # Help and version are handled as dedicated top-level flags.
      if help_requested
        options.help_requested = true
        options.argv = help_argv_for(selected_command)
      else
        options.argv = selected_command_argv
      end
      options.command_options = command_options
      options.raw_argv = raw_cli_args.dup
      options.wifi_wand_opts_env = @env['WIFIWAND_OPTS']

      options
    end

    private def help_or_version?(help_requested, options)
      help_requested || options.version_requested
    end

    private def parse_options!(parser, args, selected_command)
      parser.permute!(args)
    rescue OptionParser::ParseError => e
      raise invalid_option_error(e, selected_command)
    end

    private def invalid_option_error(error, selected_command)
      option = normalized_option_token(error.args.first)
      unless error.is_a?(OptionParser::InvalidOption) && command_scoped_option?(option) && selected_command
        return ConfigurationError.new("#{error.message}. Use -h or --help to see available options.")
      end

      command = find_command(selected_command)
      source = option_source_for(option)
      message = "#{option} is not valid for #{command.metadata.long_string}."
      message = "#{message} This option came from WIFIWAND_OPTS." if source == :environment
      ConfigurationError.new(message)
    end

    private def validate_command_options!(selected_command, invocation_options, command_options, command_argv)
      return unless selected_command

      command = find_command(selected_command)
      errors = command.validate_options(
        invocation_options: invocation_options,
        command_options:    command_options,
        args:               command_argv[1..],
        context:            self
      )
      return if errors.empty?

      raise ConfigurationError, errors.join("\n")
    end

    private def command_scoped_option?(option)
      commands.any? do |command|
        command_option_specs_for(command.class).fetch(:scoped_options).include?(option)
      end
    end

    private def command_argv_for(args, selected_command)
      return args unless selected_command

      command_index = args.index(selected_command)
      unless command_index
        raise ConfigurationError,
          "Internal parser error: selected command #{selected_command.inspect} " \
            'was not present after option parsing.'
      end

      validate_no_arguments_before_command!(args, command_index, selected_command)

      command_args = args.dup
      command_args.delete_at(command_index)
      [selected_command, *command_args]
    end

    private def validate_no_arguments_before_command!(args, command_index, selected_command)
      unexpected_arguments = args[0...command_index]
      return if unexpected_arguments.empty?

      command = find_command(selected_command)
      raise ConfigurationError,
        "Unexpected argument(s) before #{command.metadata.long_string}: #{unexpected_arguments.join(', ')}"
    end

    private def selected_command_from(args)
      argument_expected = false
      after_option_terminator = false
      index = 0

      while index < args.length
        arg = args[index]
        if arg == '--'
          argument_expected = false
          after_option_terminator = true
          index += 1
          next
        end

        if argument_expected
          argument_expected = false
          index += 1
          next
        end

        return arg if command_aliases.include?(arg)

        argument_expected = !after_option_terminator && (
          option_argument_expected?(arg) ||
            optional_option_argument_expected?(arg, args[(index + 1)..])
        )
        index += 1
      end

      nil
    end

    private def option_argument_expected?(arg)
      value_taking_options.any? do |option|
        option_matches?(option, arg) && !option_value_inline?(option, arg)
      end
    end

    private def optional_option_argument_expected?(arg, following_args)
      return false unless optional_value_command_options.include?(arg)

      optional_value, *remaining_args = following_args
      optional_value &&
        !optional_value.start_with?('-') &&
        remaining_args.any? { |token| command_aliases.include?(token) }
    end

    private def value_taking_options
      VALUE_TAKING_INVOCATION_OPTIONS + value_taking_command_options
    end

    private def normalize_command_option_args!(args, selected_command)
      command_class = selected_command_class(selected_command)
      return unless command_class.respond_to?(:normalize_command_option_args!)

      command_class.normalize_command_option_args!(args, selected_command: selected_command)
    end

    private def add_command_options(parser, selected_command, command_options)
      command_class = selected_command_class(selected_command)
      return unless command_class.respond_to?(:add_command_options)

      command_class.add_command_options(parser, command_options)
    end

    private def selected_command_class(selected_command)
      selected_command && find_command(selected_command)&.class
    end

    private def value_taking_command_options
      @value_taking_command_options ||= commands.flat_map do |command|
        command_option_specs_for(command.class).fetch(:value_taking_options)
      end.freeze
    end

    private def optional_value_command_options
      @optional_value_command_options ||= commands.flat_map do |command|
        command_option_specs_for(command.class).fetch(:optional_value_options)
      end.freeze
    end

    private def command_option_specs_for(command_class)
      return default_command_option_specs unless command_class.respond_to?(:command_option_specs)

      default_command_option_specs.merge(command_class.command_option_specs)
    end

    private def default_command_option_specs
      {
        optional_value_options: [],
        scoped_options:         [],
        value_taking_options:   [],
      }
    end

    private def help_argv_for(selected_command)
      if selected_command
        ['help', selected_command]
      else
        ['help']
      end
    end

    private def command_aliases
      @command_aliases ||= commands.flat_map(&:aliases).freeze
    end

    private def formatter_for(raw_value)
      choice = normalized_format_choice(raw_value)

      unless FORMATTERS.key?(choice)
        raise ConfigurationError,
          "Invalid output format '#{raw_value}'. Available formats: #{available_format_choices.join(', ')}"
      end

      FORMATTERS[choice]
    end

    # Relies on FORMAT_LONG_NAMES being defined in display order (a, i, j, J, p, P, y).
    private def available_format_choices
      FORMAT_LONG_NAMES.map { |name, code| "#{code}=#{name}" }
    end

    # Translates a canonical long name to its single-letter code; passes unknown values
    # through unchanged so the caller's FORMATTERS check rejects them.
    private def normalized_format_choice(raw_value)
      str = raw_value.to_s
      FORMAT_LONG_NAMES.fetch(str, str)
    end

    private def prepend_env_options(args)
      raw_options = @env['WIFIWAND_OPTS']
      return if string_nil_or_blank?(raw_options)

      env_args = Shellwords.shellsplit(raw_options)
      return if env_args.empty?

      @last_env_args = env_args
      args.unshift(*env_args)
      env_args
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid WIFIWAND_OPTS value: #{e.message}"
    end

    private def invocation_option_sources_for(option_names, cli_args:)
      option_names.to_h do |option_name|
        source = invocation_option_present?(option_name, cli_args) ? :command_line : :environment
        [option_name, source]
      end
    end

    private def invocation_option_present?(option_name, args)
      INVOCATION_OPTION_ALIASES.fetch(option_name, []).any? do |option|
        option_present?(option, args)
      end
    end

    private def option_source_for(option)
      if option_present?(option, Array(@argv))
        :command_line
      elsif option_present?(option, @last_env_args || [])
        :environment
      end
    end

    private def normalized_option_token(option)
      option.to_s.sub(/=.*/, '')
    end

    private def option_present?(option, args)
      args.any? { |arg| option_matches?(option, arg) }
    end

    private def option_matches?(option, arg)
      return false unless arg.start_with?('-')

      token = normalized_option_token(arg)
      if option.start_with?('--')
        token == option || (token.length > 2 && token.start_with?('--') && option.start_with?(token))
      elsif value_taking_options.include?(option)
        token == option || arg.start_with?(option)
      else
        token == option
      end
    end

    private def option_value_inline?(option, arg)
      arg.include?('=') || (
        option.start_with?('-') &&
          !option.start_with?('--') &&
          arg.start_with?(option) &&
          arg.length > option.length
      )
    end
  end
end
