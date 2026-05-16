# frozen_string_literal: true

module WifiWand
  module Platforms
    module Mac
      class SystemProfilerWifiDataNavigator
        LOCAL_NETWORKS_KEY = 'spairport_airport_local_wireless_networks'
        OTHER_LOCAL_NETWORKS_KEY = 'spairport_airport_other_local_wireless_networks'
        INTERFACES_KEY = 'spairport_airport_interfaces'
        CURRENT_NETWORK_KEY = 'spairport_current_network_information'
        SIGNAL_NOISE_KEY = 'spairport_signal_noise'
        SECURITY_MODE_KEY = 'spairport_security_mode'
        PLACEHOLDER_NETWORK_NAMES = %w[<hidden> <redacted>].freeze

        def self.placeholder_network_name?(name)
          value = name.to_s.strip
          value.empty? || PLACEHOLDER_NETWORK_NAMES.include?(value.downcase)
        end

        def self.associated?(interface_data)
          return false unless interface_data

          current_network = interface_data[CURRENT_NETWORK_KEY]
          return true if current_network.is_a?(Hash) && !current_network.empty?
          return true if !current_network.is_a?(Hash) && current_network && !current_network.to_s.empty?

          false
        end

        def self.current_network_name(interface_data, include_placeholder: false)
          current_network = interface_data&.fetch(CURRENT_NETWORK_KEY, nil)
          return nil unless current_network

          network_name = current_network.is_a?(Hash) ? current_network['_name'] : current_network
          return network_name if include_placeholder

          placeholder_network_name?(network_name) ? nil : network_name
        end

        def self.current_network_present?(interface_data)
          !!interface_data&.fetch(CURRENT_NETWORK_KEY, nil)
        end

        def self.network_list_key(interface_data = nil, associated: nil)
          if associated.nil?
            associated = interface_data ? associated?(interface_data) : false
          end

          associated ? OTHER_LOCAL_NETWORKS_KEY : LOCAL_NETWORKS_KEY
        end

        def self.sorted_network_names(networks)
          network_array(networks)
            .sort_by { |network| -signal_strength(network) }
            .map { |network| network['_name'] }
            .reject { |name| placeholder_network_name?(name) }
            .compact
            .uniq
        end

        def self.signal_strength(network)
          # 'spairport_signal_noise' is a slash-separated "signal/noise" string (e.g. "-65/-95").
          # Take the first component as the signal strength in dBm; default to "0/0" if absent.
          signal_dbm(network) || 0
        end

        def self.current_network_signal_dbm(interface_data)
          current_network = interface_data&.fetch(CURRENT_NETWORK_KEY, nil)
          return nil unless current_network.is_a?(Hash)

          signal_dbm(current_network)
        end

        def self.signal_dbm(network)
          return nil unless network.is_a?(Hash)

          signal = network.fetch(SIGNAL_NOISE_KEY, nil).to_s.split('/').first
          return nil unless signal&.match?(/\A-?\d+\z/)

          signal.to_i
        end
        private_class_method :signal_dbm

        def self.network_array(value)
          value.is_a?(Array) ? value.select { |network| network.is_a?(Hash) } : []
        end

        def initialize(data)
          @data = data
        end

        def interfaces
          interface_data = system_profiler_wifi_data_entries
            .detect { |entry| entry.key?(INTERFACES_KEY) }
            &.fetch(INTERFACES_KEY, [])

          self.class.network_array(interface_data)
        end

        def interface_data(interface)
          interfaces.detect { |candidate| candidate['_name'] == interface }
        end

        def associated?(interface)
          self.class.associated?(interface_data(interface))
        end

        def current_network_name(interface, include_placeholder: false)
          self.class.current_network_name(
            interface_data(interface),
            include_placeholder: include_placeholder
          )
        end

        def current_network_present?(interface)
          self.class.current_network_present?(interface_data(interface))
        end

        def visible_networks(interface, associated: nil)
          wifi_interface_data = interface_data(interface)
          return [] unless wifi_interface_data

          key = self.class.network_list_key(wifi_interface_data, associated: associated)
          networks = wifi_interface_data.fetch(key, [])
          self.class.network_array(networks)
        end

        def visible_network_names(interface, associated: nil)
          self.class.sorted_network_names(visible_networks(interface, associated: associated))
        end

        def network_security(interface, ssid, associated: nil)
          network = visible_networks(interface, associated: associated)
            .detect { |candidate| candidate['_name'] == ssid }
          network&.fetch(SECURITY_MODE_KEY, nil)
        end

        def network_hidden?(interface, ssid)
          wifi_interface_data = interface_data(interface)
          return false unless wifi_interface_data
          return false unless wifi_interface_data[CURRENT_NETWORK_KEY]

          !visible_network_names_for_hidden_check(wifi_interface_data).include?(ssid)
        end

        private def system_profiler_wifi_data_entries
          entries = @data.is_a?(Hash) ? @data['SPAirPortDataType'] : nil
          Array(entries).select { |entry| entry.is_a?(Hash) }
        end

        private def visible_network_names_for_hidden_check(interface_data)
          preferred_key = self.class.network_list_key(interface_data)
          preferred_networks = self.class.network_array(interface_data[preferred_key])
          fallback_networks = self.class.network_array(interface_data[LOCAL_NETWORKS_KEY]) +
            self.class.network_array(interface_data[OTHER_LOCAL_NETWORKS_KEY])

          (preferred_networks + fallback_networks).filter_map do |network|
            network['_name']
          end.uniq
        end
      end
    end
  end
end
