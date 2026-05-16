# frozen_string_literal: true

require_relative 'system_profiler_wifi_data_navigator'

module WifiWand
  module Platforms
    module Mac
      class CurrentNetworkDetails
        def initialize(
          system_profiler_wifi_data_proc:,
          system_profiler_wifi_data_cache_scope_proc:,
          connected_network_name_proc:,
          wifi_interface_proc:,
          security_normalizer_proc:
        )
          @system_profiler_wifi_data_proc = system_profiler_wifi_data_proc
          @system_profiler_wifi_data_cache_scope_proc = system_profiler_wifi_data_cache_scope_proc
          @connected_network_name_proc = connected_network_name_proc
          @wifi_interface_proc = wifi_interface_proc
          @security_normalizer_proc = security_normalizer_proc
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

        private def normalized_security_type(security_info)
          if security_info.to_s.strip.empty?
            'NONE'
          else
            @security_normalizer_proc.call(security_info)
          end
        end

        private def system_profiler_wifi_data_navigator
          SystemProfilerWifiDataNavigator.new(system_profiler_wifi_data)
        end

        private def system_profiler_wifi_data
          @system_profiler_wifi_data_proc.call
        end

        private def with_system_profiler_wifi_data_cache_scope(&)
          @system_profiler_wifi_data_cache_scope_proc.call(&)
        end

        private def connected_network_name
          @connected_network_name_proc.call
        end

        private def wifi_interface
          @wifi_interface_proc.call
        end
      end
    end
  end
end
