# frozen_string_literal: true

require 'json'
require_relative 'log_file_manager'

module WifiWand
  # EventLogger continuously monitors WiFi status and logs state changes.
  #
  # This service polls the WiFi model at regular intervals and emits events
  # when meaningful state changes are detected (e.g., WiFi turned on/off,
  # network connected/disconnected, internet became available/unavailable).
  #
  # Architecture:
  # 1. Maintains previous state to detect changes
  # 2. Polls status_line_data() at configurable intervals
  # 3. Compares current state with previous state
  # 4. Logs events only when state actually changes (no duplicate logging)
  # 5. Handles Ctrl+C gracefully to close log files properly
  #
  # The event structure is designed to support future hook execution for
  # automated responses to network state changes (notifications, reconnects, etc.)
  #
  # Example usage:
  #   logger = EventLogger.new(model, interval: 5, output: $stdout)
  #   logger.run  # Blocks until Ctrl+C is pressed
  class EventLogger

    EVENT_TYPES = {
      wifi_on: 'WiFi ON',
      wifi_off: 'WiFi OFF',
      connected: 'Connected to %{network_name}',
      disconnected: 'Disconnected from %{network_name}',
      internet_on: 'Internet available',
      internet_off: 'Internet unavailable'
    }.freeze

    attr_reader :model, :interval, :verbose, :hook_filespec, :output, :log_file_manager

    def initialize(model, interval: 5, verbose: false, hook_filespec: nil, log_file_path: nil,
                   output: nil, log_file_manager: nil)
      @model = model
      @interval = interval
      @verbose = verbose
      @hook_filespec = hook_filespec || File.expand_path('~/.config/wifi-wand/hooks/on-event')
      @output = output || $stdout
      # Only create LogFileManager if file logging is requested
      @log_file_manager = if log_file_manager
                            log_file_manager
                          elsif log_file_path
                            LogFileManager.new(
                              log_file_path: log_file_path,
                              verbose: @verbose,
                              output: @output
                            )
                          else
                            nil
                          end
      @previous_state = nil
      @running = false
    end

    # Start polling loop. This method blocks until stop is called or Ctrl+C is pressed.
    def run
      @running = true
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      log_message("[#{timestamp}] Event logging started (polling every #{@interval}s)")

      begin
        # Fetch and log initial state
        initial_state = fetch_current_state
        if initial_state
          log_initial_state(initial_state)
          @previous_state = initial_state
        end

        while @running
          current_state = fetch_current_state

          if current_state.nil?
            log_message("Failed to fetch WiFi state") if @verbose
            sleep(@interval)
            next
          end

          detect_and_emit_events(current_state)
          @previous_state = current_state

          sleep(@interval)
        end
      rescue Interrupt
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        log_message("[#{timestamp}] Event logging stopped")
        @running = false
      ensure
        cleanup
      end
    end

    # Log initial state at startup
    def log_initial_state(state)
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      message = "Current state: WiFi #{state[:wifi_on] ? 'ON' : 'OFF'}" +
                (state[:network_name] ? ", connected to \"#{state[:network_name]}\"" : '') +
                (state[:internet_connected] ? ", internet available" : '')
      log_message("[#{timestamp}] #{message}")
    end

    # Cleanup resources
    def cleanup
      if @log_file_manager
        @log_file_manager.close
        @log_file_manager = nil
      end
    end

    # Stop polling loop
    def stop
      @running = false
    end

    private

    # Fetch current WiFi state from model
    def fetch_current_state
      begin
        @model.status_line_data
      rescue StandardError => e
        log_message("Error fetching status: #{e.message}") if @verbose
        nil
      end
    end

    # Detect state changes and emit events
    def detect_and_emit_events(current_state)
      return if @previous_state.nil?

      # Check WiFi on/off
      if current_state[:wifi_on] != @previous_state[:wifi_on]
        event_type = current_state[:wifi_on] ? :wifi_on : :wifi_off
        emit_event(event_type, {}, @previous_state, current_state)
      end

      # Check network connection
      prev_network = @previous_state[:network_name]
      curr_network = current_state[:network_name]

      # Only track non-pending states
      if prev_network != :pending && curr_network != :pending
        if prev_network != curr_network
          if prev_network.nil? && curr_network
            emit_event(:connected, { network_name: curr_network }, @previous_state, current_state)
          elsif prev_network && curr_network.nil?
            emit_event(:disconnected, { network_name: prev_network }, @previous_state, current_state)
          elsif prev_network && curr_network
            # Switched networks
            emit_event(:disconnected, { network_name: prev_network }, @previous_state, current_state)
            emit_event(:connected, { network_name: curr_network }, @previous_state, current_state)
          end
        end
      end

      # Check internet connection
      if current_state[:internet_connected] != @previous_state[:internet_connected]
        event_type = current_state[:internet_connected] ? :internet_on : :internet_off
        emit_event(event_type, {}, @previous_state, current_state)
      end
    end

    # Create and process an event
    # Structure is ready for future hook execution
    def emit_event(event_type, details, previous_state, current_state)
      event = {
        type: event_type,
        timestamp: Time.now,
        previous_state: previous_state,
        current_state: current_state,
        details: details
      }

      log_event(event)

      # Hook execution would go here in the future:
      # execute_hook(event) if hook_exists?
    end

    # Format and output an event
    def log_event(event)
      formatted_message = format_event_message(event)
      log_message(formatted_message)
    end

    # Format event for human-readable output
    def format_event_message(event)
      timestamp = event[:timestamp].strftime('%Y-%m-%d %H:%M:%S')
      event_type = event[:type]
      details = event[:details]

      template = EVENT_TYPES[event_type]
      return "#{timestamp} UNKNOWN EVENT: #{event_type}" unless template

      message = if details.empty?
        template
      else
        template % details
      end

      "[#{timestamp}] #{message}"
    end

    # Output a message to the configured output stream and log file
    def log_message(message)
      @output.puts(message) if @output
      @output.flush if @output&.respond_to?(:flush)
      @log_file_manager.write(message) if @log_file_manager
    end
  end
end
