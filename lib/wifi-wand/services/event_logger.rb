# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../connectivity_states'
require_relative 'log_file_manager'

module WifiWand
  # EventLogger continuously monitors WiFi status and logs state changes.
  # Each poll uses a lightweight snapshot path that checks WiFi power, current
  # SSID, and fast internet reachability only. It intentionally avoids the
  # richer status pipeline so long-running `log` sessions do not perform DNS
  # checks or captive-portal subprocess fan-out on every interval.
  class EventLogger
    EVENT_TYPES = {
      wifi_on:      'WiFi ON',
      wifi_off:     'WiFi OFF',
      connected:    'Connected to %<network_name>s',
      disconnected: 'Disconnected from %<network_name>s',
      internet_on:  'Internet available',
      internet_off: 'Internet unavailable',
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
          verbose:       @verbose,
          output:        @output,
        )
      end
      @previous_state = nil
      @running = false
      @file_logging_warning_emitted = false
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
            log_message('Failed to fetch WiFi state')
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

    def log_initial_state(state)
      timestamp = Time.now.utc.iso8601
      wifi = state[:wifi_on] ? 'on' : 'off'
      network = state[:network_name] ? "connected to #{state[:network_name]}" : 'not connected'
      internet = internet_state_label(state[:internet_state])
      log_message("[#{timestamp}] Current state: WiFi #{wifi}, #{network}, internet #{internet}")
    end

    def cleanup
      if @log_file_manager
        @log_file_manager.close
        @log_file_manager = nil
      end
    end

    def stop = @running = false

    private

    def fetch_current_state
      wifi_on = @model.wifi_on?

      {
        wifi_on:        wifi_on,
        network_name:   wifi_on ? @model.connected_network_name : nil,
        internet_state: wifi_on ? lightweight_internet_state : ConnectivityStates::INTERNET_UNREACHABLE,
      }
    rescue => e
      log_message("Error fetching status: #{e.message}") if @verbose
      nil
    end

    def lightweight_internet_state
      if @model.fast_connectivity?
        ConnectivityStates::INTERNET_REACHABLE
      else
        ConnectivityStates::INTERNET_UNREACHABLE
      end
    end

    def detect_and_emit_events(current_state)
      return if @previous_state.nil?

      if current_state[:wifi_on] != @previous_state[:wifi_on]
        event_type = current_state[:wifi_on] ? :wifi_on : :wifi_off
        emit_event(event_type, {}, @previous_state, current_state)
      end

      if current_state[:network_name] != @previous_state[:network_name]
        if @previous_state[:network_name]
          emit_event(:disconnected, { network_name: @previous_state[:network_name] },
            @previous_state, current_state)
        end

        if current_state[:network_name]
          emit_event(:connected, { network_name: current_state[:network_name] },
            @previous_state, current_state)
        end
      end

      if emit_internet_event?(current_state[:internet_state], @previous_state[:internet_state])
        event_type = if current_state[:internet_state] == ConnectivityStates::INTERNET_REACHABLE
          :internet_on
        else
          :internet_off
        end
        emit_event(event_type, {}, @previous_state, current_state)
      end
    end

    def internet_state_label(value)
      case value
      when ConnectivityStates::INTERNET_REACHABLE then 'available'
      when ConnectivityStates::INTERNET_UNREACHABLE then 'unavailable'
      else 'unknown'
      end
    end

    def emit_internet_event?(current_value, previous_value)
      [
        ConnectivityStates::INTERNET_REACHABLE,
        ConnectivityStates::INTERNET_UNREACHABLE,
      ].include?(current_value) &&
        [
          ConnectivityStates::INTERNET_REACHABLE,
          ConnectivityStates::INTERNET_UNREACHABLE,
        ].include?(previous_value) &&
        current_value != previous_value
    end

    def emit_event(event_type, details, previous_state, current_state)
      event = {
        type:           event_type,
        timestamp:      Time.now,
        previous_state: previous_state,
        current_state:  current_state,
        details:        details,
      }

      log_event(event)
    end

    def log_event(event)
      formatted_message = format_event_message(event)
      log_message(formatted_message)
    end

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

    # Preserve the current stdout-first behavior, then enforce file-sink health explicitly.
    def log_message(message)
      @output.puts(message) if @output
      @output.flush if @output&.respond_to?(:flush)
      write_to_log_file(message) if @log_file_manager
    end

    def write_to_log_file(message)
      @log_file_manager.write(message)
    rescue WifiWand::LogWriteError => e
      handle_log_file_failure(e)
    end

    # Once the file sink fails, detach it immediately. Continue only when stdout is still available.
    def handle_log_file_failure(error)
      close_error = detach_log_file_manager

      if @output
        emit_file_logging_warning(compose_log_file_failure_message(error, close_error))
        return
      end

      raise error
    end

    def detach_log_file_manager
      manager = @log_file_manager
      @log_file_manager = nil
      return unless manager

      manager.close
      nil
    rescue => e
      e
    end

    def compose_log_file_failure_message(error, close_error)
      return error.message unless close_error

      "#{error.message}. Cleanup also failed: #{close_error.message}"
    end

    # Emit the fallback warning once so long-running sessions stay readable.
    def emit_file_logging_warning(error_message)
      return if @file_logging_warning_emitted

      @file_logging_warning_emitted = true
      warning =
        "WARNING: File logging is disabled. Stdout is the only remaining log destination. #{error_message}"
      @output.puts(warning)
      @output.flush if @output.respond_to?(:flush)
    end
  end
end
