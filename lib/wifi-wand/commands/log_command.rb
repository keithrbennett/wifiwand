# frozen_string_literal: true

require 'optparse'
require_relative 'command'
require_relative '../services/event_logger'
require_relative '../services/log_file_manager'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  class LogCommand < Command
    command_metadata(
      short_string: 'lo',
      long_string:  'log',
      description:  'start event logging (monitors wifi on/off, connected/disconnected, internet on/off)',
      usage:        'Usage: wifi-wand log [--interval N] [--file [PATH]] [--stdout] [--verbose]'
    )

    binds :model, output: :out_stream, verbose: :verbose_mode

    def initialize(*args, **attributes)
      resolved_model = args.empty? ? attributes[:model] : args.first
      defaults = { output: $stdout, verbose: false }
      super(**defaults.merge(attributes).merge(model: resolved_model))
    end

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
      logger_output = output_to_stdout ? output : nil

      logger = build_logger(
        interval:      interval,
        verbose_flag:  verbose_flag,
        log_file_path: log_file_path,
        logger_output: logger_output
      )

      logger.run
    end

    private def parse_options(options)
      interval = TimingConstants::EVENT_LOG_POLLING_INTERVAL
      log_file_path = nil
      output_to_stdout = true
      verbose_flag = verbose
      stdout_explicit = false
      file_destination_requested = false
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

      if help_requested
        output.puts(parser.help)
        return :skip_execution
      end

      if file_destination_requested && !stdout_explicit
        output_to_stdout = false
      end

      [interval, log_file_path, output_to_stdout, verbose_flag]
    end

    private def build_parser(interval_setter:, file_setter:, stdout_setter:, verbose_setter:, help_setter:)
      OptionParser.new do |opts|
        opts.banner = metadata.usage
        opts.separator ''
        opts.separator metadata.description
        opts.separator ''
        opts.separator 'Options:'

        opts.on('--interval N', Float, 'Poll interval in seconds (default: 5)') do |v|
          interval_setter.call(v)
        end

        opts.on('--file [PATH]', 'Enable file logging (default: wifiwand-events.log)') do |v|
          file_setter.call(v)
        end

        opts.on('--stdout', 'Keep stdout when file destination is used') do
          stdout_setter.call
        end

        opts.on('--verbose', '-v', 'Enable verbose logging') do
          verbose_setter.call
        end

        opts.on('-h', '--help', 'Show help for the log command') do
          help_setter.call
        end
      end
    end

    private def build_logger(interval:, verbose_flag:, log_file_path:, logger_output:)
      WifiWand::EventLogger.new(
        model,
        interval:      interval,
        verbose:       verbose_flag,
        log_file_path: log_file_path,
        output:        logger_output
      )
    rescue WifiWand::LogFileInitializationError => e
      raise WifiWand::ConfigurationError, e.message unless logger_output

      warn_file_logging_fallback(e.message)
      WifiWand::EventLogger.new(
        model,
        interval: interval,
        verbose:  verbose_flag,
        output:   logger_output
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
  end
end
