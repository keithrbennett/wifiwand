# frozen_string_literal: true

require 'optparse'
require_relative '../services/event_logger'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  # LogCommand handles parsing and executing the 'log' subcommand.
  #
  # Responsibilities:
  # - Parse command-line options using OptionParser
  # - Validate option values (e.g., interval must be positive)
  # - Create and configure EventLogger with parsed options
  # - Handle output destination (stdout, file, hooks)
  #
  # Options:
  # - --interval N: Poll interval in seconds (default: 5)
  # - --file [PATH]: Enable file logging (default filename: wifiwand-events.log)
  # - --stdout: Explicitly enable stdout (required when other destinations are used)
  # - --hook PATH: Hook script path
  # - --verbose: Enable verbose logging
  #
  # Output behavior:
  # - Default: stdout only (no file)
  # - --file: file only (stdout disabled unless --stdout is also provided)
  # - --hook: hook only (stdout disabled unless --stdout is also provided)
  # - --file --stdout: both file and stdout
  # - --hook --stdout: hook and stdout
  #
  # Example usage:
  #   command = LogCommand.new(model)
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
      interval, log_file_path, hook_filespec, output_to_stdout, verbose_flag = parse_options(options)

      # Create and run event logger
      logger = WifiWand::EventLogger.new(
        model,
        interval: interval,
        verbose: verbose_flag,
        hook_filespec: hook_filespec,
        log_file_path: log_file_path,
        output: (output_to_stdout ? output : nil)
      )

      # Run the logger (blocks until Ctrl+C)
      logger.run
    end

    private

    # Parse and validate command line options using OptionParser
    # Returns: [interval, log_file_path, hook_filespec, output_to_stdout, verbose]
    def parse_options(options)
      interval = TimingConstants::EVENT_LOG_POLLING_INTERVAL
      log_file_path = nil
      hook_filespec = nil
      output_to_stdout = true  # Default: stdout only
      verbose_flag = @verbose  # Start with initialization value, override if --verbose specified
      stdout_explicit = false
      alternate_destination_requested = false

      parser = OptionParser.new do |opts|
        opts.on('--interval N', Float) do |v|
          interval = validate_interval(v)
        end

        opts.on('--file [PATH]') do |v|
          # If --file is specified, use provided path or default filename
          log_file_path = v || LogFileManager::DEFAULT_LOG_FILE
          alternate_destination_requested = true
        end

        opts.on('--stdout') do
          # Explicitly enable stdout output
          output_to_stdout = true
          stdout_explicit = true
        end

        opts.on('--hook PATH') do |v|
          hook_filespec = v
          alternate_destination_requested = true
        end

        opts.on('--verbose', '-v') do
          # Enable verbose mode for logging output
          verbose_flag = true
        end
      end

      begin
        parser.parse!(options)
      rescue OptionParser::ParseError => e
        raise WifiWand::ConfigurationError.new(
          "#{e.message}. Use 'wifi-wand help' or 'wifi-wand -h' for help."
        )
      end

      if alternate_destination_requested && !stdout_explicit
        output_to_stdout = false
      end

      [interval, log_file_path, hook_filespec, output_to_stdout, verbose_flag]
    end

    # Validate that interval is positive
    def validate_interval(interval)
      return interval if interval > 0

      raise WifiWand::ConfigurationError.new(
        "Interval must be greater than 0. Use 'wifi-wand help' or 'wifi-wand -h' for help."
      )
    end
  end
end
