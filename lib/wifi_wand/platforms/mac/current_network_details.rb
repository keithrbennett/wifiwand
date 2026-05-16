# frozen_string_literal: true

require_relative 'system_profiler_wifi_data_navigator'
require_relative '../../signal_quality'

module WifiWand
  module Platforms
    module Mac
      class CurrentNetworkDetails
        def initialize(
          system_profiler_wifi_data_reader:,
          system_profiler_wifi_data_cache_runner:,
          connected_network_name_reader:,
          wifi_interface_provider:,
          security_normalizer:
        )
          @system_profiler_wifi_data_reader = system_profiler_wifi_data_reader
          @system_profiler_wifi_data_cache_runner = system_profiler_wifi_data_cache_runner
          @connected_network_name_reader = connected_network_name_reader
          @wifi_interface_provider = wifi_interface_provider
          @security_normalizer = security_normalizer
        end

        def connection_security_type
          with_system_profiler_wifi_data_cache_scope do
            network_name = connected_network_name
            return nil unless network_name

            security_info = system_profiler_wifi_data_navigator.network_security(wifi_interface, network_name)
            return nil if security_info.nil?

            normalized_security_type(security_info)
          end
        end

        def network_hidden?
          with_system_profiler_wifi_data_cache_scope do
            network_name = connected_network_name
            return false unless network_name

            system_profiler_wifi_data_navigator.network_hidden?(wifi_interface, network_name)
          end
        end

        def signal_quality
          with_system_profiler_wifi_data_cache_scope do
            return nil unless connected_network_name

            iface_data = system_profiler_wifi_data_navigator.interface_data(wifi_interface)
            dbm = SystemProfilerWifiDataNavigator.current_network_signal_dbm(iface_data)
            dbm ? SignalQuality.new(value: dbm, unit: :dbm) : nil
          end
        end

        private def normalized_security_type(security_info)
          if security_info.to_s.strip.empty?
            'NONE'
          else
            @security_normalizer.call(security_info)
          end
        end

        private def system_profiler_wifi_data_navigator
          SystemProfilerWifiDataNavigator.new(system_profiler_wifi_data)
        end

        private def system_profiler_wifi_data
          @system_profiler_wifi_data_reader.call
        end

        private def with_system_profiler_wifi_data_cache_scope(&)
          @system_profiler_wifi_data_cache_runner.call(&)
        end

        private def connected_network_name
          @connected_network_name_reader.call
        end

        private def wifi_interface
          @wifi_interface_provider.call
        end
      end
    end
  end
end
