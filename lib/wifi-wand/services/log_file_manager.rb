# frozen_string_literal: true

require 'fileutils'
require_relative '../errors'

module WifiWand
  # LogFileManager handles writing timestamped events to a log file.
  #
  # Responsibilities:
  # - Opens log file in append mode (creates if it does not exist)
  # - Writes messages with timestamps
  # - Flushes after each write to ensure data is written to disk
  # - Closes file handle properly
  #
  # Design notes:
  # - Does not create parent directories (directory must exist)
  # - File open, write, and close errors are propagated to the caller
  # - Each write is flushed immediately for real-time log visibility
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

    # Propagate write failures so EventLogger can either fall back to stdout or stop.
    def write(message)
      raise WifiWand::LogWriteError, 'Log file is not available' unless @file_handle

      @file_handle.puts(message)
      @file_handle.flush
    rescue => e
      raise WifiWand::LogWriteError, "Failed to write to log file #{@log_file_path}: #{e.message}"
    end

    def close
      return unless @file_handle

      @file_handle.close
      @file_handle = nil
    end

    private def setup_log_file
      open_log_file
      log_message("Log file initialized at #{@log_file_path}") if @verbose
    rescue WifiWand::LogFileInitializationError
      raise
    rescue => e
      raise WifiWand::LogFileInitializationError,
        "Failed to initialize log file #{@log_file_path}: #{e.message}"
    end

    private def open_log_file
      @file_handle = File.open(@log_file_path, 'a')
    rescue => e
      raise WifiWand::LogFileInitializationError,
        "Cannot open log file #{@log_file_path}: #{e.message}"
    end

    private def log_message(message)
      @output.puts(message) if @output
      @output.flush if @output&.respond_to?(:flush)
    end
  end
end
