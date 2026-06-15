# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'base'
require_relative '../services/event_logger'
require_relative '../services/log_file_manager'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  module Commands
    class Log < Base
      command_metadata(
        short_string: 'lo',
        long_string:  'log',
        description:  'start JSON Lines event logging (monitors wifi, connection, and internet state)',
        usage:        [
          'Usage: wifi-wand log [--interval N] [--file [PATH]]',
          '[--stdout] [--verbose BOOLEAN]',
        ].join(' ')
      )

      VALUE_TAKING_OPTIONS = %w[--interval].freeze
      OPTIONAL_VALUE_OPTIONS = %w[--file].freeze
      FLAG_OPTIONS = %w[--stdout].freeze
      OPTION_DEFINITIONS = {
        interval: {
          parser_description: 'Poll interval in seconds (default: 5)',
          summary:            '--interval N (default 5 seconds)',
          switch:             '--interval N',
        },
        file:     {
          parser_description: 'Enable file logging (default: wifiwand-events.log)',
          summary:            '--file [PATH] (default: wifiwand-events.log)',
          switch:             '--file [PATH]',
        },
        stdout:   {
          parser_description: 'Keep stdout when file destination is used',
          summary:            '--stdout (keep stdout when file destination is used)',
          switch:             '--stdout',
        },
      }.freeze
      COMMAND_OPTION_SPECS = {
        optional_value_options: OPTIONAL_VALUE_OPTIONS,
        scoped_options:         (VALUE_TAKING_OPTIONS + OPTIONAL_VALUE_OPTIONS + FLAG_OPTIONS).freeze,
        value_taking_options:   VALUE_TAKING_OPTIONS,
      }.freeze

      binds :model, output: :out_stream, verbose_flag: :verbose?, command_options: :command_options
      allow_invocation_options :wifi_interface, :utc

      def self.command_option_specs = COMMAND_OPTION_SPECS

      def self.help_summary_lines
        [
          declared_metadata.description,
          "options: #{option_summary(:interval)}, #{option_summary(:file)},",
          option_summary(:stdout),
          'Outputs JSON Lines: one JSON object per event',
          'Internet events are derived from reachable/unreachable state; ' \
            'indeterminate is preserved as unknown',
          'Ctrl+C to stop',
        ]
      end

      def self.add_command_options(parser, command_options)
        parser.on(option_switch(:interval), Float, option_parser_description(:interval)) do |value|
          command_options[:interval] = value
        end

        parser.on(option_switch(:file), option_parser_description(:file)) do |value|
          command_options[:log_file_path] = LogFileManager::DEFAULT_LOG_FILE
          command_options[:log_file_path] = value unless value.nil?
          command_options[:file_destination_requested] = true
        end

        parser.on(option_switch(:stdout), option_parser_description(:stdout)) do
          command_options[:stdout_explicit] = true
        end
      end

      def self.option_switch(option_name)
        OPTION_DEFINITIONS.fetch(option_name).fetch(:switch)
      end

      def self.option_parser_description(option_name)
        OPTION_DEFINITIONS.fetch(option_name).fetch(:parser_description)
      end

      def self.option_summary(option_name)
        OPTION_DEFINITIONS.fetch(option_name).fetch(:summary)
      end

      def self.normalize_command_option_args!(args, selected_command:)
        index = 0

        while index < args.length
          if args[index] == '--file'
            value = args[index + 1]
            if consume_file_option_value?(args, index, selected_command, value)
              args[index] = "--file=#{value}"
              args.delete_at(index + 1)
            elsif value == selected_command && pre_command_option?(args, index, selected_command)
              args[index] = "--file=#{LogFileManager::DEFAULT_LOG_FILE}"
            end
          end

          index += 1
        end
      end

      def self.consume_file_option_value?(args, index, selected_command, value)
        return false if value.nil? || value.start_with?('-')
        return true unless selected_command
        return true unless pre_command_option?(args, index, selected_command)

        # A pre-command optional value is a real path only when another copy of
        # the selected command remains later to serve as the command token.
        args[(index + 2)..].include?(selected_command)
      end

      def self.pre_command_option?(args, index, selected_command)
        command_index = args.index(selected_command)
        command_index && index < command_index
      end

      def verbose? = @verbose_flag

      def help_text
        # Reuse the command parser as the single source of truth for help text.
        build_parser(command_options: {}, verbose_setter: ->(_value) {}, help_setter: -> {}).help
      end

      def call(*options)
        parse_result = parse_options(options)
        return if parse_result == :skip_execution

        interval, log_file_path, output_to_stdout, verbose_flag = parse_result
        logger_out_stream = output_to_stdout ? output : nil

        logger = build_logger(
          interval:          interval,
          verbose_flag:      verbose_flag,
          log_file_path:     log_file_path,
          logger_out_stream: logger_out_stream
        )

        logger.run
      end

      private def parse_options(options)
        self.class.normalize_command_option_args!(options, selected_command: nil)

        output_to_stdout = true
        verbose_flag = verbose?
        help_requested = false
        parsed_command_options = {}

        parser = build_parser(
          command_options: parsed_command_options,
          verbose_setter:  ->(value) { verbose_flag = value },
          help_setter:     -> { help_requested = true }
        )

        begin
          parser.parse!(options)
        rescue OptionParser::ParseError => e
          raise WifiWand::ConfigurationError, "#{e.message}. #{help_hint}"
        end

        validate_max_arguments!(options, 0)

        effective_command_options = configured_command_options.merge(parsed_command_options)
        interval = validate_interval(
          effective_command_options.fetch(:interval, TimingConstants::EVENT_LOG_POLLING_INTERVAL)
        )
        log_file_path = effective_command_options[:log_file_path]
        stdout_explicit = effective_command_options.fetch(:stdout_explicit, false)
        file_destination_requested = effective_command_options.fetch(:file_destination_requested, false)

        if help_requested
          output.puts(parser.help)
          return :skip_execution
        end

        if file_destination_requested && !stdout_explicit
          output_to_stdout = false
        end

        [interval, log_file_path, output_to_stdout, verbose_flag]
      end

      private def build_parser(
        command_options:,
        verbose_setter:,
        help_setter:
      )
        OptionParser.new do |opts|
          opts.banner = metadata.usage
          opts.separator ''
          opts.separator metadata.description
          opts.separator ''
          opts.separator 'Options:'

          self.class.add_command_options(opts, command_options)

          opts.on('-v', '--verbose BOOLEAN', TrueClass, 'Enable verbose logging') do |value|
            verbose_setter.call(value)
          end

          opts.on('-h', '--help', 'Show help for the log command') do
            help_setter.call
          end
        end
      end

      private def build_logger(interval:, verbose_flag:, log_file_path:, logger_out_stream:)
        WifiWand::EventLogger.new(
          model,
          interval:       interval,
          verbose:        verbose_flag,
          log_file_path:  log_file_path,
          out_stream:     logger_out_stream,
          runtime_config: model.runtime_config
        )
      rescue WifiWand::LogFileInitializationError => e
        raise WifiWand::ConfigurationError, e.message unless logger_out_stream

        warn_file_logging_fallback(e.message)
        WifiWand::EventLogger.new(
          model,
          interval:       interval,
          verbose:        verbose_flag,
          out_stream:     logger_out_stream,
          runtime_config: model.runtime_config
        )
      end

      private def warn_file_logging_fallback(error_message)
        message = "File logging is disabled. Stdout is the only remaining log destination. #{error_message}"
        warning = JSON.generate(
          timestamp: fallback_warning_timestamp,
          event:     'warning',
          message:   message
        )
        output.puts(warning)
        output.flush if output.respond_to?(:flush)
      end

      private def fallback_warning_timestamp
        utc? ? Time.now.getutc.iso8601 : Time.now.getlocal.iso8601
      end

      private def utc?
        model.runtime_config.utc
      end

      private def validate_interval(interval)
        return interval if interval > 0

        raise WifiWand::ConfigurationError,
          "Interval must be greater than 0. #{help_hint}"
      end

      private def configured_command_options
        if cli && command_options.nil?
          raise WifiWand::ConfigurationError,
            "Internal command binding error: #{metadata.long_string} command_options was nil."
        end

        command_options || {}
      end

      private def help_hint
        cli&.help_hint || "Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end
    end
  end
end
