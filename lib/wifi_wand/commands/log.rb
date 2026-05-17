# frozen_string_literal: true

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
        description:  'start event logging (monitors wifi on/off, connected/disconnected, internet on/off)',
        usage:        [
          'Usage: wifi-wand log [--interval N] [--file [PATH]]',
          '[--stdout] [--verbose]',
        ].join(' ')
      )

      VALUE_TAKING_OPTIONS = %w[--interval].freeze
      OPTIONAL_VALUE_OPTIONS = %w[--file].freeze
      FLAG_OPTIONS = %w[--stdout].freeze
      SCOPED_OPTIONS = (VALUE_TAKING_OPTIONS + OPTIONAL_VALUE_OPTIONS + FLAG_OPTIONS).freeze

      binds :model, output: :out_stream, verbose_flag: :verbose?, command_options: :command_options
      allow_invocation_options :wifi_interface, :utc

      def self.add_options(parser, interval_setter:, file_setter:, stdout_setter:)
        parser.on('--interval N', Float, 'Poll interval in seconds (default: 5)') do |value|
          interval_setter.call(value)
        end

        parser.on('--file [PATH]', 'Enable file logging (default: wifiwand-events.log)') do |value|
          file_setter.call(value)
        end

        parser.on('--stdout', 'Keep stdout when file destination is used') do
          stdout_setter.call
        end
      end

      def self.scoped_options = SCOPED_OPTIONS

      def self.normalize_option_args!(args, selected_command:)
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
        # These setters are intentionally inert because help generation should not
        # mutate command state or trigger execution behavior.
        build_parser(
          interval_setter: ->(_value) {},
          file_setter:     ->(_value) {},
          stdout_setter:   -> {},
          verbose_setter:  -> {},
          help_setter:     -> {}
        ).help
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
        self.class.normalize_option_args!(options, selected_command: nil)

        interval = validate_interval(
          configured_command_options.fetch(:interval, TimingConstants::EVENT_LOG_POLLING_INTERVAL)
        )
        log_file_path = configured_command_options[:log_file_path]
        output_to_stdout = true
        verbose_flag = verbose?
        stdout_explicit = configured_command_options.fetch(:stdout_explicit, false)
        file_destination_requested = configured_command_options.fetch(:file_destination_requested, false)
        help_requested = false

        parser = build_parser(
          interval_setter: ->(value) { interval = validate_interval(value) },
          file_setter:     ->(value) do
            log_file_path = value || LogFileManager::DEFAULT_LOG_FILE
            file_destination_requested = true
          end,
          stdout_setter:   -> do
            output_to_stdout = true
            stdout_explicit = true
          end,
          verbose_setter:  -> { verbose_flag = true },
          help_setter:     -> { help_requested = true }
        )

        begin
          parser.parse!(options)
        rescue OptionParser::ParseError => e
          raise WifiWand::ConfigurationError, "#{e.message}. Use 'wifi-wand help' or 'wifi-wand -h' for help."
        end

        validate_max_arguments!(options, 0)

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
        interval_setter:,
        file_setter:,
        stdout_setter:,
        verbose_setter:,
        help_setter:
      )
        OptionParser.new do |opts|
          opts.banner = metadata.usage
          opts.separator ''
          opts.separator metadata.description
          opts.separator ''
          opts.separator 'Options:'

          self.class.add_options(
            opts,
            interval_setter: interval_setter,
            file_setter:     file_setter,
            stdout_setter:   stdout_setter
          )

          opts.on('-v', '--verbose', 'Enable verbose logging') do
            verbose_setter.call
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
          runtime_config: model.respond_to?(:runtime_config) ? model.runtime_config : nil
        )
      rescue WifiWand::LogFileInitializationError => e
        raise WifiWand::ConfigurationError, e.message unless logger_out_stream

        warn_file_logging_fallback(e.message)
        WifiWand::EventLogger.new(
          model,
          interval:       interval,
          verbose:        verbose_flag,
          out_stream:     logger_out_stream,
          runtime_config: model.respond_to?(:runtime_config) ? model.runtime_config : nil
        )
      end

      private def warn_file_logging_fallback(error_message)
        warning =
          "WARNING: File logging is disabled. Stdout is the only remaining log destination. #{error_message}"
        output.puts(warning)
        output.flush if output.respond_to?(:flush)
      end

      private def validate_interval(interval)
        return interval if interval > 0

        raise WifiWand::ConfigurationError,
          "Interval must be greater than 0. Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end

      private def configured_command_options
        command_options || {}
      end
    end
  end
end
