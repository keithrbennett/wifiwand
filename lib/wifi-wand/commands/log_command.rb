# frozen_string_literal: true

require 'optparse'
require_relative '../services/event_logger'
require_relative '../services/log_file_manager'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  # LogCommand handles parsing and executing the 'log' subcommand.
  #
  # Responsibilities:
  # - Parse command-line options using OptionParser
  # - Validate option values (e.g., interval must be positive)
  # - Create and configure EventLogger with parsed options
  # - Handle output destination (stdout, file)
  #
  # Options:
  # - --interval N: Poll interval in seconds (default: 5)
  # - --file [PATH]: Enable file logging (default filename: wifiwand-events.log)
  # - --stdout: Explicitly enable stdout (required when other destinations are used)
  # - --verbose: Enable verbose logging
  #
  # Output behavior:
  # - Default: stdout only (no file)
  # - --file: file only (stdout disabled unless --stdout is also provided)
  # - --file --stdout: both file and stdout
  #
  # Example usage:
  #   command = WifiWand::LogCommand.new(model)
  #   command.execute('--interval', '2', '--file', '--stdout')
  class LogCommand
    attr_reader :model, :output, :verbose

    def initialize(model, output: $stdout, verbose: false)
      @model = model
      @output = output
      @verbose = verbose
    end

    # Execute the log command with the provided options
    def execute(*options)
      interval, log_file_path, output_to_stdout, verbose_flag = parse_options(options)
      logger_output = output_to_stdout ? output : nil

      logger = build_logger(
        interval:      interval,
        verbose_flag:  verbose_flag,
        log_file_path: log_file_path,
        logger_output: logger_output
      )

      logger.run
    end

    private

    # Parse and validate command line options using OptionParser
    # Returns: [interval, log_file_path, output_to_stdout, verbose]
    def parse_options(options)
      interval = TimingConstants::EVENT_LOG_POLLING_INTERVAL
      log_file_path = nil
      output_to_stdout = true
      verbose_flag = @verbose
      stdout_explicit = false
      file_destination_requested = false

      parser = OptionParser.new do |opts|
        opts.on('--interval N', Float) do |v|
          interval = validate_interval(v)
        end

        opts.on('--file [PATH]') do |v|
          log_file_path = v || LogFileManager::DEFAULT_LOG_FILE
          file_destination_requested = true
        end

        opts.on('--stdout') do
          output_to_stdout = true
          stdout_explicit = true
        end

        opts.on('--verbose', '-v') do
          verbose_flag = true
        end
      end

      begin
        parser.parse!(options)
      rescue OptionParser::ParseError => e
        raise WifiWand::ConfigurationError, "#{e.message}. Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end

      if file_destination_requested && !stdout_explicit
        output_to_stdout = false
      end

      [interval, log_file_path, output_to_stdout, verbose_flag]
    end

    # --file becomes a required sink unless stdout is also available as an explicit fallback.
    def build_logger(interval:, verbose_flag:, log_file_path:, logger_output:)
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

    # Surface the fallback immediately so the user does not assume the file sink is still active.
    def warn_file_logging_fallback(error_message)
      warning =
        "WARNING: File logging is disabled. Stdout is the only remaining log destination. #{error_message}"
      output.puts(warning)
      output.flush if output.respond_to?(:flush)
    end

    def validate_interval(interval)
      return interval if interval > 0

      raise WifiWand::ConfigurationError,
        "Interval must be greater than 0. Use 'wifi-wand help' or 'wifi-wand -h' for help."
    end
  end
end
