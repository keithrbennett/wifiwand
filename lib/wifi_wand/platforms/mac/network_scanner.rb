# frozen_string_literal: true

require_relative 'airport_data_navigator'
require_relative '../../errors'

module WifiWand
  module Platforms
    module Mac
      class NetworkScanner
        def self.placeholder_network_name?(name)
          AirportDataNavigator.placeholder_network_name?(name)
        end

        def initialize(
          helper_client_proc:,
          airport_data_proc:,
          airport_data_cache_scope_proc:,
          wifi_interface_proc:
        )
          @helper_client_proc = helper_client_proc
          @airport_data_proc = airport_data_proc
          @airport_data_cache_scope_proc = airport_data_cache_scope_proc
          @wifi_interface_proc = wifi_interface_proc
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
          iface = wifi_interface
          data = airport_data
          AirportDataNavigator.new(data).visible_network_names(iface)
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
  end
end
