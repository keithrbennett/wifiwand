# frozen_string_literal: true

require 'optparse'
require_relative '../services/event_logger'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  class LogCommand
    attr_reader :model, :output, :verbose

    def initialize(model, output: $stdout, verbose: false)
      @model = model
      @output = output
      @verbose = verbose
    end

    # Execute the log command with the provided options
    def execute(*options)
      interval, log_file_path, hook_filespec, output_to_stdout = parse_options(options)

      # Create and run event logger
      logger = WifiWand::EventLogger.new(
        model,
        interval: interval,
        verbose: verbose,
        hook_filespec: hook_filespec,
        log_file_path: log_file_path,
        output: (output_to_stdout ? output : nil)
      )

      # Run the logger (blocks until Ctrl+C)
      logger.run
    end

    private

    # Parse and validate command line options using OptionParser
    # Returns: [interval, log_file_path, hook_filespec, output_to_stdout]
    def parse_options(options)
      interval = TimingConstants::EVENT_LOG_POLLING_INTERVAL
      log_file_path = nil
      hook_filespec = nil
      output_to_stdout = true  # Default: stdout only

      parser = OptionParser.new do |opts|
        opts.on('--interval N', Float) do |v|
          interval = validate_interval(v)
        end

        opts.on('--file [PATH]') do |v|
          # If --file is specified, use provided path or default filename
          log_file_path = v || LogFileManager::DEFAULT_LOG_FILE
          output_to_stdout = false
        end

        opts.on('--stdout') do
          # Additive: also output to stdout
          output_to_stdout = true
        end

        opts.on('--hook PATH') do |v|
          hook_filespec = v
        end

        opts.on('--verbose', '-v') do
          # verbose mode is already set via initialization
        end
      end

      begin
        parser.parse!(options)
      rescue OptionParser::ParseError => e
        raise WifiWand::ConfigurationError.new(
          "#{e.message}. Use 'wifi-wand help' or 'wifi-wand -h' for help."
        )
      end

      [interval, log_file_path, hook_filespec, output_to_stdout]
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
