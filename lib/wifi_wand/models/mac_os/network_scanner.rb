# frozen_string_literal: true

require_relative 'airport_data_navigator'
require_relative '../../errors'

module WifiWand
  class MacOsNetworkScanner
    private attr_reader :command_runner

    # Matches one data row from `airport -s`.
    #
    # The command prints a whitespace-aligned table whose first column is the
    # SSID, followed by BSSID, RSSI, channel, and other metadata. SSIDs can
    # contain spaces, so the first capture is intentionally lazy and stops at
    # the first token that looks like a BSSID. The second capture is RSSI, which
    # can be negative. Later columns are not needed for scan ordering.
    AIRPORT_SCAN_ROW_REGEX =
      /\A\s*(.*?)\s+(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\s+(-?\d+)\s+/i

    def self.parse_airport_scan_output(output)
      scanned_networks = output.split("\n").drop(1).filter_map do |line|
        match = line.match(AIRPORT_SCAN_ROW_REGEX)
        next unless match

        name = match[1].strip
        next if placeholder_network_name?(name)

        [name, match[2].to_i]
      end

      scanned_networks.sort_by { |_name, signal| -signal }.map(&:first).uniq
    end

    def self.placeholder_network_name?(name)
      MacOsAirportDataNavigator.placeholder_network_name?(name)
    end

    def initialize(
      helper_client_proc:,
      command_runner:,
      airport_data_proc:,
      airport_data_cache_scope_proc:,
      wifi_interface_proc:,
      airport_command:
    )
      @helper_client_proc = helper_client_proc
      @command_runner = command_runner
      @airport_data_proc = airport_data_proc
      @airport_data_cache_scope_proc = airport_data_cache_scope_proc
      @wifi_interface_proc = wifi_interface_proc
      @airport_command = airport_command
    end

    def available_network_names
      scan.fetch('networks')
    end

    def scan
      with_airport_data_cache_scope do
        helper_result = helper_client.scan_networks
        helper_networks = helper_available_network_names_from_result(helper_result)
        return scan_result(helper_networks, source: 'mac_helper') if helper_networks

        fallback_networks = fallback_available_network_names
        if helper_result.location_services_blocked?
          return location_services_blocked_scan(fallback_networks)
        end

        scan_result(fallback_networks, source: 'fallback')
      end
    end

    def helper_available_network_names
      result = helper_client.scan_networks

      helper_available_network_names_from_result(result)
    end

    def airport_available_network_names(timeout_in_secs: nil)
      output = command_runner.call(
        [@airport_command, '-s'],
        timeout_in_secs: timeout_in_secs
      ).stdout
      networks = self.class.parse_airport_scan_output(output)
      networks.empty? ? nil : networks
    rescue WifiWand::Error
      nil
    end

    private def helper_available_network_names_from_result(result)
      return nil if result.location_services_blocked?

      networks = result.payload
      return nil unless networks&.any?

      names = networks
        .map { |network| network['ssid'].to_s }
        .reject { |ssid| self.class.placeholder_network_name?(ssid) }
        .uniq

      names.empty? ? nil : names
    end

    private def fallback_available_network_names
      airport_networks = airport_available_network_names
      return airport_networks if airport_networks

      iface = wifi_interface
      data = airport_data
      MacOsAirportDataNavigator.new(data).visible_network_names(iface)
    end

    private def scan_result(networks, source:, status: 'ok', trusted: true, warning: nil)
      {
        'networks'          => Array(networks),
        'scan_status'       => status,
        'scan_source'       => source,
        'ssid_data_trusted' => trusted,
        'warning'           => warning,
      }
    end

    private def location_services_blocked_scan(networks)
      scan_result(
        networks,
        source:  'fallback',
        status:  'location_services_blocked',
        trusted: false,
        warning: location_services_blocked_scan_warning
      )
    end

    private def location_services_blocked_scan_warning
      'macOS blocked wifiwand-helper from reading WiFi SSIDs through Location Services; ' \
        'fallback scan results may be incomplete or unavailable. Run `wifi-wand-macos-setup`, ' \
        'grant Location Services to `wifiwand-helper`, and retry.'
    end

    private def helper_client
      @helper_client_proc.call
    end

    private def airport_data
      @airport_data_proc.call
    end

    private def with_airport_data_cache_scope(&)
      @airport_data_cache_scope_proc.call(&)
    end

    private def wifi_interface
      @wifi_interface_proc.call
    end
  end
end
