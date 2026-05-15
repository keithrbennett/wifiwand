# frozen_string_literal: true

require_relative 'airport_data_navigator'

module WifiWand
  module Platforms
    module Mac
      class CurrentNetworkDetails
        def initialize(
          airport_data_proc:,
          airport_data_cache_scope_proc:,
          connected_network_name_proc:,
          wifi_interface_proc:,
          security_normalizer_proc:
        )
          @airport_data_proc = airport_data_proc
          @airport_data_cache_scope_proc = airport_data_cache_scope_proc
          @connected_network_name_proc = connected_network_name_proc
          @wifi_interface_proc = wifi_interface_proc
          @security_normalizer_proc = security_normalizer_proc
        end

        def connection_security_type
          with_airport_data_cache_scope do
            network_name = connected_network_name
            return nil unless network_name

            security_info = airport_data_navigator.network_security(wifi_interface, network_name)
            return nil if security_info.nil?

            normalized_security_type(security_info)
          end
        end

        def network_hidden?
          with_airport_data_cache_scope do
            network_name = connected_network_name
            return false unless network_name

            airport_data_navigator.network_hidden?(wifi_interface, network_name)
          end
        end

        private def normalized_security_type(security_info)
          if security_info.to_s.strip.empty?
            'NONE'
          else
            @security_normalizer_proc.call(security_info)
          end
        end

        private def airport_data_navigator
          AirportDataNavigator.new(airport_data)
        end

        private def airport_data
          @airport_data_proc.call
        end

        private def with_airport_data_cache_scope(&)
          @airport_data_cache_scope_proc.call(&)
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
