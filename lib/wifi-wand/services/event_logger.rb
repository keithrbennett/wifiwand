# frozen_string_literal: true

require 'json'
require 'time'
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
  # 2. Polls at configurable intervals checking wifi_on?, connected_network_name, and fast_connectivity?
  # 3. Compares current state with previous state
  # 4. Logs events only when state actually changes (no duplicate logging)
  # 5. Handles Ctrl+C gracefully to close log files properly
  #
  # Event emission order when multiple changes occur in one poll:
  #   1. WiFi power (wifi_on/wifi_off)
  #   2. Network connection (connected/disconnected)
  #   3. Internet connectivity (internet_on/internet_off)
  #
  # Example usage:
  #   logger = EventLogger.new(model, interval: 5, output: $stdout)
  #   logger.run  # Blocks until Ctrl+C is pressed
  class EventLogger

    EVENT_TYPES = {
      wifi_on:      'WiFi ON',
      wifi_off:     'WiFi OFF',
      connected:    'Connected to %{network_name}',
      disconnected: 'Disconnected from %{network_name}',
      internet_on:  'Internet available',
      internet_off: 'Internet unavailable'
    }.freeze

    attr_reader :model, :interval, :verbose, :output, :log_file_manager

    def initialize(model, interval: 5, verbose: false, log_file_path: nil,
                   output: $stdout, log_file_manager: nil)
      @model = model
      @interval = interval
      @verbose = verbose
      @output = output
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
      timestamp = Time.now.utc.iso8601
      log_message("[#{timestamp}] Event logging started (polling every #{@interval}s)")

      begin
        while @running
          current_state = fetch_current_state

          if current_state
            if @previous_state
              detect_and_emit_events(current_state)
            else
              log_initial_state(current_state)
            end
            @previous_state = current_state
          elsif @verbose
            log_message("Failed to fetch WiFi state")
          end

          break unless @running
          sleep(@interval)
        end
      rescue Interrupt
        timestamp = Time.now.utc.iso8601
        log_message("[#{timestamp}] Event logging stopped")
        @running = false
      ensure
        cleanup
      end
    end

    # Log initial state at startup
    def log_initial_state(state)
      timestamp = Time.now.utc.iso8601
      wifi = state[:wifi_on] ? 'on' : 'off'
      network = state[:network_name] ? "connected to #{state[:network_name]}" : 'not connected'
      internet = state[:internet_connected] ? 'available' : 'unavailable'
      log_message("[#{timestamp}] Current state: WiFi #{wifi}, #{network}, internet #{internet}")
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

    # Fetch current WiFi state from model.
    # Uses status_line_data which performs checks concurrently for better performance.
    def fetch_current_state
      @model.status_line_data
    rescue StandardError => e
      log_message("Error fetching status: #{e.message}") if @verbose
      nil
    end

    # Detect state changes and emit events
    # Checks wifi_on, network_name, and internet_connected in that order
    def detect_and_emit_events(current_state)
      return if @previous_state.nil?

      if current_state[:wifi_on] != @previous_state[:wifi_on]
        event_type = current_state[:wifi_on] ? :wifi_on : :wifi_off
        emit_event(event_type, {}, @previous_state, current_state)
      end

      if current_state[:network_name] != @previous_state[:network_name]
        if @previous_state[:network_name]
          emit_event(:disconnected, { network_name: @previous_state[:network_name] }, @previous_state, current_state)
        end

        if current_state[:network_name]
          emit_event(:connected, { network_name: current_state[:network_name] }, @previous_state, current_state)
        end
      end

      if current_state[:internet_connected] != @previous_state[:internet_connected]
        event_type = current_state[:internet_connected] ? :internet_on : :internet_off
        emit_event(event_type, {}, @previous_state, current_state)
      end
    end

    # Create and process an event
    def emit_event(event_type, details, previous_state, current_state)
      event = {
        type: event_type,
        timestamp: Time.now,
        previous_state: previous_state,
        current_state: current_state,
        details: details
      }

      log_event(event)
    end

    # Format and output an event
    def log_event(event)
      formatted_message = format_event_message(event)
      log_message(formatted_message)
    end

    # Format event for human-readable output
    def format_event_message(event)
      timestamp = event[:timestamp].utc.iso8601
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
