# frozen_string_literal: true

require 'async'
require_relative '../connectivity_states'

module WifiWand
  class StatusLineDataBuilder
    attr_reader :model, :verbose_mode, :output, :expected_network_errors

    def initialize(model, verbose: false, output: $stdout, expected_network_errors: [])
      @model = model
      @verbose_mode = verbose
      @output = output
      @expected_network_errors = expected_network_errors
    end

    def call(progress_callback: nil)
      partial = initial_data

      progress_callback&.call(partial.dup)

      unless partial[:wifi_on]
        partial.merge!(data_when_wifi_off)
        progress_callback&.call(partial.dup)
        return partial
      end

      Async do |task|
        ssid_task = task.async { network_name }
        connectivity_task = task.async { connectivity_data }

        partial[:network_name] = ssid_task.wait
        progress_callback&.call(partial.dup)

        partial.merge!(connectivity_task.wait)

        final_data = partial.dup
        progress_callback&.call(final_data)
        final_data
      end.wait
    rescue *expected_network_errors, WifiWand::Error => e
      output.puts "Warning: status_line_data failed: #{e.class}: #{e.message}" if verbose_mode
      progress_callback&.call(nil)
      nil
    end

    private

    def initial_data
      {
        wifi_on:                       model.wifi_on?,
        dns_working:                   nil,
        internet_state:                ConnectivityStates::INTERNET_PENDING,
        internet_check_complete:       false,
        network_name:                  :pending,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :unknown,
      }
    end

    def data_when_wifi_off
      {
        dns_working:                   false,
        network_name:                  nil,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :no,
      }
    end

    def network_name
      model.connected_network_name
    rescue WifiWand::Error, *expected_network_errors => e
      output.puts "Warning: SSID lookup failed: #{e.class}: #{e.message}" if verbose_mode
      nil
    end

    def connectivity_data
      tcp_working = tcp_connectivity?
      dns_working = dns_working?

      return data_when_internet_unreachable(dns_working: dns_working) unless tcp_working && dns_working

      portal_state = captive_portal_state

      {
        dns_working:                   dns_working,
        internet_state:                ConnectivityStates.internet_state_from(
          tcp_working:          tcp_working,
          dns_working:          dns_working,
          captive_portal_state: portal_state,
        ),
        internet_check_complete:       true,
        captive_portal_state:          portal_state,
        captive_portal_login_required: captive_portal_login_required(portal_state),
      }
    end

    def tcp_connectivity?
      model.internet_tcp_connectivity?
    rescue *expected_network_errors, WifiWand::Error
      false
    end

    def dns_working?
      model.dns_working?
    rescue *expected_network_errors, WifiWand::Error
      false
    end

    def captive_portal_state
      model.captive_portal_state
    rescue *expected_network_errors, WifiWand::Error
      ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
    end

    def captive_portal_login_required(portal_state)
      case portal_state
      when ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
        :unknown
      when ConnectivityStates::CAPTIVE_PORTAL_FREE
        :no
      else
        :yes
      end
    end

    def data_when_internet_unreachable(dns_working:)
      {
        dns_working:                   dns_working,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :no,
      }
    end
  end
end
