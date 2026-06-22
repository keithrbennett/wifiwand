# frozen_string_literal: true

require_relative 'system_profiler_wifi_data_navigator'
require_relative '../../errors'

module WifiWand
  module Platforms
    module Mac
      class NetworkScanner
        def self.placeholder_network_name?(name)
          SystemProfilerWifiDataNavigator.placeholder_network_name?(name)
        end

        def initialize(
          helper_client_provider:,
          system_profiler_wifi_data_reader:,
          system_profiler_wifi_data_cache_runner:,
          wifi_interface_provider:
        )
          @helper_client_provider = helper_client_provider
          @system_profiler_wifi_data_reader = system_profiler_wifi_data_reader
          @system_profiler_wifi_data_cache_runner = system_profiler_wifi_data_cache_runner
          @wifi_interface_provider = wifi_interface_provider
        end

        def available_network_names
          scan.fetch('networks')
        end

        def scan
          with_system_profiler_wifi_data_cache_scope do
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
          data = system_profiler_wifi_data
          SystemProfilerWifiDataNavigator.new(data).visible_network_names(iface)
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
            'fallback scan results may be incomplete or unavailable. Run `wifiwand-macos-setup`, ' \
            'grant Location Services to `wifiwand-helper`, and retry.'
        end

        private def helper_client
          @helper_client_provider.call
        end

        private def system_profiler_wifi_data
          @system_profiler_wifi_data_reader.call
        end

        private def with_system_profiler_wifi_data_cache_scope(&)
          @system_profiler_wifi_data_cache_runner.call(&)
        end

        private def wifi_interface
          @wifi_interface_provider.call
        end
      end
    end
  end
end
