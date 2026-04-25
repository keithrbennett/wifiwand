# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../connectivity_states'
require_relative '../timing_constants'
require_relative 'log_file_manager'

module WifiWand
  # EventLogger continuously monitors WiFi status and logs state changes.
  # Each poll captures WiFi power and current SSID, then derives internet
  # events from the explicit connectivity-state model. Stable internet states
  # reuse the fast TCP probe so frequent polls do not pay for the full
  # TCP+DNS+captive-portal path every time, but startup and suspected
  # transitions are still confirmed with internet_connectivity_state so
  # internet_on/internet_off keep their explicit-state semantics.
  # Internet reachability is checked independently of WiFi association so
  # alternate uplinks such as Ethernet still produce accurate Internet events.
  class EventLogger
    SSID_UNAVAILABLE_LABEL = '[SSID unavailable]'

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
          output:        @output
        )
      end
      @previous_state = nil
      @running = false
      @file_logging_warning_emitted = false
      @consecutive_state_fetch_failures = 0
      @state_fetch_warning_emitted = false
    end

    # Start polling loop. This method blocks until stop is called or Ctrl+C is pressed.
    def run
      @running = true
      timestamp = Time.now.utc.iso8601
      log_message("[#{timestamp}] Event logging started (polling every #{@interval}s)")

      begin
        next_poll_at = monotonic_now
        while @running
          current_state = fetch_current_state

          if @previous_state
            detect_and_emit_events(current_state)
          else
            log_initial_state(current_state)
          end
          @previous_state = current_state

          break unless @running

          next_poll_at += @interval
          sleep_until(next_poll_at)
        end
      rescue Interrupt
        timestamp = Time.now.utc.iso8601
        log_message("[#{timestamp}] Event logging stopped")
        @running = false
      ensure
        cleanup
      end
    end

    private def sleep_until(deadline)
      remaining = deadline - monotonic_now
      sleep([remaining, 0].max)
    end

    def log_initial_state(state)
      timestamp = Time.now.utc.iso8601
      wifi = wifi_state_label(state[:wifi_on])
      network = network_state_label(state)
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

    private def fetch_current_state
      fetch_failures = []
      wifi_on = fetch_status_value(:wifi_on, @previous_state&.dig(:wifi_on), fetch_failures) do
        @model.wifi_on?
      end
      connected = current_connected_state(wifi_on, fetch_failures)

      state = {
        wifi_on:        wifi_on,
        connected:      connected,
        network_name:   current_network_name_state(wifi_on, connected, fetch_failures),
        internet_state: fetch_status_value(
          :internet_state,
          @previous_state&.dig(:internet_state),
          fetch_failures
        ) { current_internet_state },
      }

      record_state_fetch_outcome(fetch_failures)
      state
    end

    private def current_internet_state
      return confirmed_internet_state unless @previous_state

      fast_reachability = @model.fast_connectivity?(timeout_in_secs: fast_connectivity_timeout)
      previous_internet_state = @previous_state[:internet_state]
      return previous_internet_state if stable_internet_state?(previous_internet_state, fast_reachability)

      confirmed_internet_state(fast_reachability)
    end

    private def internet_probe_timeout
      [@interval, TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT].min
    end

    private def fast_connectivity_timeout
      [@interval, TimingConstants::FAST_CONNECTIVITY_TIMEOUT].min
    end

    private def confirmed_internet_state(tcp_working = nil)
      @model.internet_connectivity_state(tcp_working, nil, timeout_in_secs: internet_probe_timeout)
    end

    private def stable_internet_state?(previous_internet_state, fast_reachability)
      (previous_internet_state == ConnectivityStates::INTERNET_REACHABLE && fast_reachability == true) ||
        (previous_internet_state == ConnectivityStates::INTERNET_UNREACHABLE && fast_reachability == false)
    end

    private def detect_and_emit_events(current_state)
      return if @previous_state.nil?

      if comparable_boolean_values?(current_state[:wifi_on], @previous_state[:wifi_on]) &&
          current_state[:wifi_on] != @previous_state[:wifi_on]
        event_type = current_state[:wifi_on] ? :wifi_on : :wifi_off
        emit_event(event_type, {}, @previous_state, current_state)
      end

      if connection_became_disconnected?(current_state)
        if @previous_state[:network_name]
          emit_event(:disconnected, { network_name: @previous_state[:network_name] },
            @previous_state, current_state)
        end
      elsif connection_became_connected?(current_state)
        if current_state[:network_name]
          emit_event(:connected, { network_name: current_state[:network_name] },
            @previous_state, current_state)
        end
      elsif network_name_changed_while_connected?(current_state)
        if named_network?(@previous_state[:network_name])
          emit_event(:disconnected, { network_name: @previous_state[:network_name] },
            @previous_state, current_state)
        end

        if named_network?(current_state[:network_name])
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

    private def internet_state_label(value)
      case value
      when ConnectivityStates::INTERNET_REACHABLE then 'available'
      when ConnectivityStates::INTERNET_UNREACHABLE then 'unavailable'
      else 'unknown'
      end
    end

    private def wifi_state_label(value)
      case value
      when true then 'on'
      when false then 'off'
      else 'unknown'
      end
    end

    private def current_network_name(connected)
      network_name = @model.connected_network_name
      network_name_available = !network_name.nil? && !network_name.to_s.empty?
      if network_name_available
        network_name
      else
        (connected ? SSID_UNAVAILABLE_LABEL : nil)
      end
    end

    private def network_state_label(state)
      return 'not connected' if state[:connected] == false
      return 'connection unknown' if state[:connected].nil?
      return "connected to #{state[:network_name]}" if state[:network_name]

      'connected (SSID unavailable)'
    end

    private def connection_became_connected?(current_state)
      comparable_boolean_values?(current_state[:connected], @previous_state[:connected]) &&
        current_state[:connected] && !@previous_state[:connected]
    end

    private def connection_became_disconnected?(current_state)
      comparable_boolean_values?(current_state[:connected], @previous_state[:connected]) &&
        !current_state[:connected] && @previous_state[:connected]
    end

    private def network_name_changed_while_connected?(current_state)
      current_state[:connected] \
        && @previous_state[:connected] \
        && named_network?(@previous_state[:network_name]) \
        && named_network?(current_state[:network_name]) \
        && current_state[:network_name] != @previous_state[:network_name]
    end

    private def named_network?(network_name)
      !network_name.nil? && network_name != SSID_UNAVAILABLE_LABEL
    end

    private def current_connected_state(wifi_on, fetch_failures)
      return false if wifi_on == false
      return @previous_state&.dig(:connected) if wifi_on.nil?

      fetch_status_value(:connected, @previous_state&.dig(:connected), fetch_failures) do
        @model.connected?
      end
    end

    private def current_network_name_state(wifi_on, connected, fetch_failures)
      return nil if wifi_on == false || connected == false

      fallback_name = connected ? @previous_state&.dig(:network_name) : nil
      return fallback_name if fetch_failed?(fetch_failures, :connected)

      fetch_status_value(:network_name, fallback_name, fetch_failures) do
        current_network_name(connected)
      end
    end

    private def fetch_status_value(field_name, fallback_value, fetch_failures)
      yield
    rescue WifiWand::Error => e
      fetch_failures << { field: field_name, error: e }
      log_message("Error fetching #{field_name}: #{e.message}") if @verbose
      fallback_value
    end

    private def fetch_failed?(fetch_failures, field_name)
      fetch_failures.any? { |failure| failure[:field] == field_name }
    end

    private def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    private def record_state_fetch_outcome(fetch_failures)
      if fetch_failures.empty?
        reset_state_fetch_failures
        return
      end

      @consecutive_state_fetch_failures += 1
      emit_state_fetch_warning if should_emit_state_fetch_warning?
    end

    private def reset_state_fetch_failures
      @consecutive_state_fetch_failures = 0
      @state_fetch_warning_emitted = false
    end

    private def should_emit_state_fetch_warning?
      !@verbose &&
        @output &&
        !@state_fetch_warning_emitted &&
        @consecutive_state_fetch_failures >= 2
    end

    private def emit_state_fetch_warning
      @state_fetch_warning_emitted = true
      warning = [
        'WARNING: Status polling is encountering repeated lookup failures.',
        'Continuing with partial state until lookups recover.',
      ].join(' ')
      @output.puts(warning)
      @output.flush if @output.respond_to?(:flush)
    end

    private def comparable_boolean_values?(current_value, previous_value)
      [true, false].include?(current_value) && [true, false].include?(previous_value)
    end

    private def emit_internet_event?(current_value, previous_value)
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

    private def emit_event(event_type, details, previous_state, current_state)
      event = {
        type:           event_type,
        timestamp:      Time.now,
        previous_state: previous_state,
        current_state:  current_state,
        details:        details,
      }

      log_event(event)
    end

    private def log_event(event)
      formatted_message = format_event_message(event)
      log_message(formatted_message)
    end

    private def format_event_message(event)
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
    private def log_message(message)
      @output.puts(message) if @output
      @output.flush if @output&.respond_to?(:flush)
      write_to_log_file(message) if @log_file_manager
    end

    private def write_to_log_file(message)
      @log_file_manager.write(message)
    rescue WifiWand::LogWriteError => e
      handle_log_file_failure(e)
    end

    # Once the file sink fails, detach it immediately. Continue only when stdout is still available.
    private def handle_log_file_failure(error)
      close_error = detach_log_file_manager

      if @output
        emit_file_logging_warning(compose_log_file_failure_message(error, close_error))
        return
      end

      raise error
    end

    private def detach_log_file_manager
      manager = @log_file_manager
      @log_file_manager = nil
      return unless manager

      manager.close
      nil
    rescue => e
      e
    end

    private def compose_log_file_failure_message(error, close_error)
      return error.message unless close_error

      "#{error.message}. Cleanup also failed: #{close_error.message}"
    end

    # Emit the fallback warning once so long-running sessions stay readable.
    private def emit_file_logging_warning(error_message)
      return if @file_logging_warning_emitted

      @file_logging_warning_emitted = true
      warning =
        "WARNING: File logging is disabled. Stdout is the only remaining log destination. #{error_message}"
      @output.puts(warning)
      @output.flush if @output.respond_to?(:flush)
    end
  end
end
