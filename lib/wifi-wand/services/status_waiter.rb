# frozen_string_literal: true

require_relative '../timing_constants'
require_relative '../connectivity_states'

module WifiWand
  class StatusWaiter
    PERMITTED_STATES = %i[wifi_on wifi_off associated disassociated internet_on internet_off].freeze

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

    def initialize(model, verbose: false, output: nil)
      @model = model
      @verbose = verbose
      @output = output
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
      message_prefix = "StatusWaiter (#{target_status}):"

      if @verbose
        timeout_display = timeout_in_secs ? "#{timeout_in_secs}s" : 'never'
        (@output || $stdout).puts "#{message_prefix} starting, timeout: #{timeout_display}, " \
          "interval: #{wait_interval_in_secs}s"
      end

      finished_predicates = {
        wifi_on:       -> { @model.wifi_on? },
        wifi_off:      -> { !@model.wifi_on? },
        associated:    -> { @model.associated? },
        disassociated: -> { !@model.associated? },
        internet_on:   -> { @model.internet_connectivity_state == ConnectivityStates::INTERNET_REACHABLE },
        internet_off:  -> { @model.internet_connectivity_state == ConnectivityStates::INTERNET_UNREACHABLE },
      }

      finished_predicate = finished_predicates[target_status]

      if finished_predicate.nil?
        allowed = PERMITTED_STATES.join(', ')
        legacy_hint = LEGACY_STATE_HINTS[target_status]
        if legacy_hint
          raise ArgumentError, "#{legacy_hint}\nValid states: #{allowed}"
        elsif stringify_permitted_values_in_error_msg
          raise ArgumentError, "Option must be one of [#{allowed}]. Was: #{target_status}"
        else
          raise ArgumentError,
            "Option must be one of #{PERMITTED_STATES.inspect}. Was: #{target_status.inspect}"
        end
      end

      if finished_predicate.call
        (@output || $stdout).puts "#{message_prefix} completed without needing to wait" if @verbose
        return nil
      elsif @verbose
        (@output || $stdout).puts "#{message_prefix} First attempt failed, entering waiting loop"
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        if timeout_in_secs && elapsed_time >= timeout_in_secs
          raise WaitTimeoutError.new(target_status, timeout_in_secs)
        end

        (@output || $stdout).puts "#{message_prefix} checking predicate..." if @verbose
        if finished_predicate.call
          if @verbose
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            (@output || $stdout).puts "#{message_prefix} wait time (seconds): #{end_time - start_time}"
          end
          return nil
        end
        sleep(wait_interval_in_secs)
      end
    end
  end
end
