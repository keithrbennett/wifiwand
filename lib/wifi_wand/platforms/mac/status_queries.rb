# frozen_string_literal: true

require 'ipaddr'

require_relative 'system_profiler_wifi_data_navigator'
require_relative '../../errors'
require_relative '../../signal_quality'
require_relative '../../services/command_executor'
require_relative '../../string_predicates'

module WifiWand
  module Platforms
    module Mac
      class StatusQueries
        include StringPredicates

        NO_CONNECTED_NETWORK = Object.new.freeze

        def initialize(
          helper_client_provider:,
          command_runner:,
          system_profiler_wifi_data_reader:,
          system_profiler_wifi_data_cache_runner:,
          wifi_interface_cache_reader:,
          wifi_interface_cache_writer:,
          wifi_interface_probe:,
          system_network_info_provider:,
          status_deadline_factory:,
          status_timeout_calculator:
        )
          @helper_client_provider = helper_client_provider
          @command_runner = command_runner
          @system_profiler_wifi_data_reader = system_profiler_wifi_data_reader
          @system_profiler_wifi_data_cache_runner = system_profiler_wifi_data_cache_runner
          @wifi_interface_cache_reader = wifi_interface_cache_reader
          @wifi_interface_cache_writer = wifi_interface_cache_writer
          @wifi_interface_probe = wifi_interface_probe
          @system_network_info_provider = system_network_info_provider
          @status_deadline_factory = status_deadline_factory
          @status_timeout_calculator = status_timeout_calculator
        end

        def status_network_identity(timeout_in_secs: nil)
          deadline = status_deadline(timeout_in_secs)

          with_system_profiler_wifi_data_cache_scope do
            return disconnected_identity unless wifi_on_before_deadline?(deadline)

            helper_result = helper_client.connected_network_name(
              timeout_seconds: status_timeout_for(deadline)
            )
            helper_ssid = helper_result.payload
            if helper_ssid && !placeholder_network_name?(helper_ssid)
              return { connected:      true,
                       network_name:   helper_ssid,
                       signal_quality: helper_result.signal_quality }
            end
            return disconnected_identity if helper_result.not_connected?

            fast_network_name = status_network_name_using_fast_commands(deadline)
            return disconnected_identity if no_connected_network?(fast_network_name)
            if fast_network_name
              return { connected:      true,
                       network_name:   fast_network_name,
                       signal_quality: nil }
            end

            status_network_identity_from_system_profiler_wifi_data(deadline)
          end
        end

        def status_wifi_on?(timeout_in_secs: nil)
          deadline = status_deadline(timeout_in_secs)

          wifi_on_before_deadline?(deadline)
        end

        private attr_reader :command_runner

        private def status_network_identity_from_system_profiler_wifi_data(deadline)
          interface_data = system_profiler_wifi_interface_data(deadline: deadline)
          connected = interface_associated_in_system_profiler_wifi_data?(interface_data) ||
            status_associated_without_ssid?(deadline)
          network_name = connected ? status_network_name_from_system_profiler_wifi_data(interface_data) : nil
          signal_quality = connected ? signal_quality_from_interface_data(interface_data) : nil

          {
            connected:      connected,
            network_name:   network_name,
            signal_quality: signal_quality,
          }
        end

        private def signal_quality_from_interface_data(interface_data)
          dbm = SystemProfilerWifiDataNavigator.current_network_signal_dbm(interface_data)
          dbm ? SignalQuality.new(value: dbm, unit: :dbm) : nil
        end

        private def status_network_name_using_fast_commands(deadline)
          iface = status_wifi_interface(deadline)
          return nil unless iface

          connected_network_name_using_networksetup(
            iface:           iface,
            timeout_in_secs: status_timeout_for(deadline)
          )
        end

        private def connected_network_name_using_networksetup(iface:, timeout_in_secs: nil)
          output = command_runner.call(
            ['networksetup', '-getairportnetwork', iface],
            timeout_in_secs: timeout_in_secs
          ).stdout.strip
          return nil if output.empty?
          return NO_CONNECTED_NETWORK if output.match?(/not associated|power is currently off/i)

          match = output.match(/\ACurrent (?:Wi-Fi|AirPort) Network:\s*(.*)\z/)
          return nil unless match

          network_name = match[1].strip
          return nil if placeholder_network_name?(network_name)

          network_name
        rescue WifiWand::Error
          nil
        end

        private def no_connected_network?(network_name)
          network_name.equal?(NO_CONNECTED_NETWORK)
        end

        private def status_associated_without_ssid?(deadline)
          iface = status_wifi_interface(deadline)
          return false unless iface
          return true if status_default_interface(deadline) == iface

          status_ipv4_addresses(deadline).any? || status_ipv6_association_addresses(deadline).any?
        rescue WifiWand::CommandExecutor::OsCommandError
          false
        end

        private def interface_associated_in_system_profiler_wifi_data?(wifi_interface_data)
          SystemProfilerWifiDataNavigator.associated?(wifi_interface_data)
        end

        private def status_network_name_from_system_profiler_wifi_data(wifi_interface_data)
          SystemProfilerWifiDataNavigator.current_network_name(wifi_interface_data)
        end

        private def disconnected_identity
          {
            connected:      false,
            network_name:   nil,
            signal_quality: nil,
          }
        end

        private def helper_client
          @helper_client_provider.call
        end

        private def with_system_profiler_wifi_data_cache_scope(&)
          @system_profiler_wifi_data_cache_runner.call(&)
        end

        private def system_profiler_wifi_data(timeout_in_secs: nil)
          @system_profiler_wifi_data_reader.call(timeout_in_secs: timeout_in_secs)
        end

        private def status_wifi_interface(deadline)
          cached_iface = @wifi_interface_cache_reader.call
          return cached_iface if cached_iface && !cached_iface.empty?

          iface = @wifi_interface_probe.call(timeout_in_secs: status_timeout_for(deadline))
          return nil if string_nil_or_empty?(iface)

          @wifi_interface_cache_writer.call(iface)
          iface
        end

        private def status_default_interface(deadline)
          iface = status_wifi_interface(deadline)
          return nil if string_nil_or_empty?(iface)

          system_network_info.default_interface(timeout_in_secs: status_timeout_for(deadline))
        end

        private def status_ipv4_addresses(deadline)
          iface = status_wifi_interface(deadline)
          return [] if string_nil_or_empty?(iface)

          system_network_info.ipv4_addresses(iface: iface, timeout_in_secs: status_timeout_for(deadline))
        end

        private def status_ipv6_addresses(deadline)
          iface = status_wifi_interface(deadline)
          return [] if string_nil_or_empty?(iface)

          system_network_info.ipv6_addresses(iface: iface, timeout_in_secs: status_timeout_for(deadline))
        end

        private def status_ipv6_association_addresses(deadline)
          status_ipv6_addresses(deadline).select do |address|
            usable_ipv6_association_address?(address)
          end
        end

        private def usable_ipv6_association_address?(address)
          parsed_address = IPAddr.new(address)
          parsed_address.ipv6? && !parsed_address.link_local?
        rescue IPAddr::InvalidAddressError
          false
        end

        private def system_network_info
          @system_network_info_provider.call
        end

        private def status_deadline(timeout_in_secs)
          @status_deadline_factory.call(timeout_in_secs)
        end

        private def status_timeout_for(deadline)
          @status_timeout_calculator.call(deadline)
        end

        private def system_profiler_wifi_interface_data(deadline:)
          data = system_profiler_wifi_data(timeout_in_secs: status_timeout_for(deadline))
          iface = status_wifi_interface(deadline)

          SystemProfilerWifiDataNavigator.new(data).interface_data(iface)
        end

        private def wifi_on_before_deadline?(deadline)
          iface = status_wifi_interface(deadline)
          return false unless iface

          system_network_info.wifi_on?(
            iface:           iface,
            timeout_in_secs: status_timeout_for(deadline)
          )
        end

        private def placeholder_network_name?(name)
          SystemProfilerWifiDataNavigator.placeholder_network_name?(name)
        end
      end
    end
  end
end
