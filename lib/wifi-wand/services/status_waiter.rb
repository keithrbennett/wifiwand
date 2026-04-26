# frozen_string_literal: true

require_relative '../timing_constants'
require_relative '../connectivity_states'
require_relative '../runtime_config'

module WifiWand
  class StatusWaiter
    PERMITTED_STATES = %i[wifi_on wifi_off associated disassociated internet_on internet_off].freeze
    private attr_reader :runtime_config

    # Migration hints for removed legacy state names.  Shown in error messages so users know
    # exactly what to use instead.
    LEGACY_STATE_HINTS = {
      on:   "':on' was removed. Use ':wifi_on' to wait for the WiFi radio to be powered on.",
      off:  "':off' was removed. Use ':wifi_off' to wait for the WiFi radio to be powered off.",
      conn: "':conn' was removed. Use ':internet_on' to wait for full Internet reachability " \
        "(TCP + DNS + captive-portal free), or ':associated' to wait for WiFi SSID association.",
      disc: "':disc' was removed. Use ':internet_off' to wait for Internet reachability to be " \
        "lost, or ':disassociated' to wait for WiFi to leave the current SSID.",
    }.freeze

    def initialize(model, verbose: false, output: $stdout, runtime_config: nil)
      @model = model
      @runtime_config = runtime_config || RuntimeConfig.new(
        verbose:    verbose,
        out_stream: output
      )
    end

    # Waits for the WiFi/Internet connection to be in the desired state.
    #
    # @param target_status one of PERMITTED_STATES:
    #   :wifi_on         – WiFi hardware is powered on
    #   :wifi_off        – WiFi hardware is powered off
    #   :associated      – WiFi is associated with an SSID (at the WiFi layer)
    #   :disassociated   – WiFi is not associated with any SSID
    #   :internet_on     – Full Internet reachability (TCP + DNS + captive-portal free)
    #   :internet_off    – Internet reachability check fails
    # @param timeout_in_secs after this many seconds the method raises WaitTimeoutError;
    #        if nil (default), waits indefinitely
    # @param wait_interval_in_secs sleeps this interval between retries; if nil, uses default
    def wait_for(target_status, timeout_in_secs: nil, wait_interval_in_secs: nil,
      stringify_permitted_values_in_error_msg: false)
      wait_interval_in_secs ||= TimingConstants::DEFAULT_WAIT_INTERVAL
      validate_timing_value!(timeout_in_secs, :timeout_in_secs)
      validate_timing_value!(wait_interval_in_secs, :wait_interval_in_secs)
      validate_target!(target_status, stringify_permitted_values_in_error_msg)
      message_prefix = "StatusWaiter (#{target_status}):"

      if verbose?
        timeout_display = timeout_in_secs ? "#{timeout_in_secs}s" : 'never'
        output.puts <<~MESSAGE.chomp
          #{message_prefix} starting, timeout: #{timeout_display}, interval: #{wait_interval_in_secs}s
        MESSAGE
      end

      finished_predicate = finished_predicates.fetch(target_status)
      expensive_predicate = %i[internet_on internet_off].include?(target_status)

      start_time = current_time
      deadline = timeout_in_secs && (start_time + timeout_in_secs)

      if predicate_satisfied?(
        finished_predicate,
        target_status:       target_status,
        timeout_in_secs:     timeout_in_secs,
        deadline:            deadline,
        expensive_predicate: expensive_predicate
      )
        output.puts "#{message_prefix} completed without needing to wait" if verbose?
        return nil
      elsif verbose?
        output.puts "#{message_prefix} First attempt failed, entering waiting loop"
      end

      loop do
        raise_timeout_if_deadline_exceeded!(target_status, timeout_in_secs, deadline)

        output.puts "#{message_prefix} checking predicate..." if verbose?
        if predicate_satisfied?(
          finished_predicate,
          target_status:       target_status,
          timeout_in_secs:     timeout_in_secs,
          deadline:            deadline,
          expensive_predicate: expensive_predicate
        )
          if verbose?
            end_time = current_time
            output.puts "#{message_prefix} wait time (seconds): #{end_time - start_time}"
          end
          return nil
        end

        sleep_duration = sleep_duration_for(wait_interval_in_secs, deadline)
        raise_timeout_if_deadline_exceeded!(target_status, timeout_in_secs, deadline) if sleep_duration <= 0

        sleep(sleep_duration)
      end
    end

    private def predicate_satisfied?(predicate, target_status:, timeout_in_secs:, deadline:,
      expensive_predicate:)
      return predicate.call unless expensive_predicate && timeout_in_secs

      remaining_time = remaining_time_until(deadline)
      raise_timeout_if_deadline_exceeded!(target_status, timeout_in_secs, deadline) if remaining_time <= 0

      predicate.call(remaining_time)
    end

    private def sleep_duration_for(wait_interval_in_secs, deadline)
      return wait_interval_in_secs unless deadline

      [wait_interval_in_secs, remaining_time_until(deadline)].min
    end

    private def raise_timeout_if_deadline_exceeded!(target_status, timeout_in_secs, deadline)
      return unless timeout_in_secs && deadline && remaining_time_until(deadline) <= 0

      raise WaitTimeoutError.new(action: target_status, timeout: timeout_in_secs)
    end

    private def remaining_time_until(deadline)
      deadline - current_time
    end

    private def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    private def verbose? = runtime_config.verbose

    private def output = runtime_config.out_stream

    private def finished_predicates
      {
        wifi_on:       -> { @model.wifi_on? },
        wifi_off:      -> { !@model.wifi_on? },
        associated:    -> { @model.associated? },
        disassociated: -> { !@model.associated? },
        internet_on:   ->(remaining_time = nil) {
          @model.internet_connectivity_state(timeout_in_secs: remaining_time) ==
            ConnectivityStates::INTERNET_REACHABLE
        },
        internet_off:  ->(remaining_time = nil) {
          @model.internet_connectivity_state(timeout_in_secs: remaining_time) ==
            ConnectivityStates::INTERNET_UNREACHABLE
        },
      }
    end

    private def validate_target!(target_status, stringify_permitted_values_in_error_msg)
      return if PERMITTED_STATES.include?(target_status)

      allowed = PERMITTED_STATES.join(', ')
      legacy_hint = LEGACY_STATE_HINTS[target_status]

      if legacy_hint
        raise ArgumentError, <<~MESSAGE.chomp
          #{legacy_hint}
          Valid states: #{allowed}
        MESSAGE
      elsif stringify_permitted_values_in_error_msg
        raise ArgumentError, "Option must be one of [#{allowed}]. Was: #{target_status}"
      else
        raise ArgumentError,
          "Option must be one of #{PERMITTED_STATES.inspect}. Was: #{target_status.inspect}"
      end
    end

    private def validate_timing_value!(value, name)
      return if value.nil? || value >= 0

      raise ArgumentError, "#{name} must be non-negative. Was: #{value.inspect}"
    end
  end
end
