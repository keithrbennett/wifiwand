# frozen_string_literal: true

require 'fileutils'

module WifiWand
  # LogFileManager handles writing timestamped events to a log file.
  #
  # Responsibilities:
  # - Opens log file in append mode (creates if doesn't exist)
  # - Writes messages with timestamps
  # - Flushes after each write to ensure data is written to disk
  # - Closes file handle properly
  # - Reports errors to stderr if issues occur
  #
  # Design notes:
  # - Does NOT create parent directories (directory must exist)
  # - File close errors are propagated to the caller (not silently swallowed)
  # - Each write is flushed immediately for real-time log visibility
  #
  # Example usage:
  #   manager = LogFileManager.new(log_file_path: 'events.log')
  #   manager.write('[2025-10-28 14:30:00] WiFi ON')
  #   manager.close
  class LogFileManager
    DEFAULT_LOG_FILE = 'wifiwand-events.log'

    attr_reader :log_file_path, :output, :verbose

    def initialize(log_file_path: nil, verbose: false, output: nil)
      @log_file_path = log_file_path || DEFAULT_LOG_FILE
      @verbose = verbose
      @output = output || $stdout
      @file_handle = nil
      setup_log_file
    end

    # Write a formatted message to the log file
    def write(message)
      return unless @file_handle

      begin
        @file_handle.puts(message)
        @file_handle.flush
      rescue => e
        log_error("Failed to write to log file: #{e.message}")
      end
    end

    # Close the log file
    def close
      return unless @file_handle

      @file_handle.close
      @file_handle = nil
    end

    private

    # Set up the log file (open file in append mode)
    def setup_log_file
      open_log_file
      log_message("Log file initialized at #{@log_file_path}") if @verbose
    rescue => e
      log_error("Failed to initialize log file: #{e.message}")
    end

    # Open the log file in append mode
    def open_log_file
      @file_handle = File.open(@log_file_path, 'a')
    rescue => e
      raise "Cannot open log file #{@log_file_path}: #{e.message}"
    end

    # Log a message to stdout
    def log_message(message)
      @output.puts(message) if @output
      @output.flush if @output&.respond_to?(:flush)
    end

    # Log an error message to stderr
    def log_error(message)
      warn("ERROR: #{message}")
      $stderr.flush if $stderr.respond_to?(:flush)
    end
  end
end
