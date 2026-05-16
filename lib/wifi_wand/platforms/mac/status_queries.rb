# frozen_string_literal: true

require 'ipaddr'

require_relative 'airport_data_navigator'
require_relative 'colon_output_parser'
require_relative '../../errors'
require_relative '../../services/command_executor'
require_relative '../../string_predicates'

module WifiWand
  module Platforms
    module Mac
      class StatusQueries
        include ColonOutputParser
        include StringPredicates

        NO_CONNECTED_NETWORK = Object.new.freeze

        def initialize(
          helper_client_proc:,
          command_runner:,
          airport_data_proc:,
          airport_data_cache_scope_proc:,
          cached_wifi_interface_proc:,
          cache_wifi_interface_proc:,
          probe_wifi_interface_proc:,
          system_network_info_proc:,
          status_deadline_proc:,
          status_timeout_proc:,
          airport_command:
        )
          @helper_client_proc = helper_client_proc
          @command_runner = command_runner
          @airport_data_proc = airport_data_proc
          @airport_data_cache_scope_proc = airport_data_cache_scope_proc
          @cached_wifi_interface_proc = cached_wifi_interface_proc
          @cache_wifi_interface_proc = cache_wifi_interface_proc
          @probe_wifi_interface_proc = probe_wifi_interface_proc
          @system_network_info_proc = system_network_info_proc
          @status_deadline_proc = status_deadline_proc
          @status_timeout_proc = status_timeout_proc
          @airport_command = airport_command
        end

        def status_network_identity(timeout_in_secs: nil)
          deadline = status_deadline(timeout_in_secs)

          with_airport_data_cache_scope do
            return disconnected_identity unless wifi_on_before_deadline?(deadline)

            helper_result = helper_client.connected_network_name(
              timeout_seconds: status_timeout_for(deadline)
            )
            helper_ssid = helper_result.payload
            if helper_ssid && !placeholder_network_name?(helper_ssid)
              return { connected: true, network_name: helper_ssid }
            end
            return disconnected_identity if helper_result.not_connected?

            fast_network_name = status_network_name_using_fast_commands(deadline)
            return disconnected_identity if no_connected_network?(fast_network_name)
            return { connected: true, network_name: fast_network_name } if fast_network_name

            status_network_identity_from_airport_data(deadline)
          end
        end

        def status_wifi_on?(timeout_in_secs: nil)
          deadline = status_deadline(timeout_in_secs)

          wifi_on_before_deadline?(deadline)
        end

        private attr_reader :command_runner

        private def status_network_identity_from_airport_data(deadline)
          interface_data = wifi_interface_airport_data(deadline: deadline)
          connected = interface_associated_in_airport_data?(interface_data) ||
            status_associated_without_ssid?(deadline)
          network_name = connected ? status_network_name_from_airport_data(interface_data) : nil

          {
            connected:    connected,
            network_name: network_name,
          }
        end

        private def status_network_name_using_fast_commands(deadline)
          iface = status_wifi_interface(deadline)
          return nil unless iface

          network_name = connected_network_name_using_networksetup(
            iface:           iface,
            timeout_in_secs: status_timeout_for(deadline)
          )
          return network_name if network_name

          connected_network_name_using_airport(timeout_in_secs: status_timeout_for(deadline))
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

        private def connected_network_name_using_airport(timeout_in_secs: nil)
          output = command_runner.call(
            [@airport_command, '-I'],
            timeout_in_secs: timeout_in_secs
          ).stdout
          return nil if string_nil_or_blank?(output)

          airport_info = colon_output_to_hash(output)
          network_name = airport_info['SSID']
          return network_name if airport_info.key?('SSID') && !placeholder_network_name?(network_name)

          nil
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

        private def interface_associated_in_airport_data?(wifi_interface_data)
          AirportDataNavigator.associated?(wifi_interface_data)
        end

        private def status_network_name_from_airport_data(wifi_interface_data)
          AirportDataNavigator.current_network_name(wifi_interface_data)
        end

        private def disconnected_identity
          {
            connected:    false,
            network_name: nil,
          }
        end

        private def helper_client
          @helper_client_proc.call
        end

        private def with_airport_data_cache_scope(&)
          @airport_data_cache_scope_proc.call(&)
        end

        private def airport_data(timeout_in_secs: nil)
          @airport_data_proc.call(timeout_in_secs: timeout_in_secs)
        end

        private def status_wifi_interface(deadline)
          cached_iface = @cached_wifi_interface_proc.call
          return cached_iface if cached_iface && !cached_iface.empty?

          iface = @probe_wifi_interface_proc.call(timeout_in_secs: status_timeout_for(deadline))
          return nil if string_nil_or_empty?(iface)

          @cache_wifi_interface_proc.call(iface)
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
          @system_network_info_proc.call
        end

        private def status_deadline(timeout_in_secs)
          @status_deadline_proc.call(timeout_in_secs)
        end

        private def status_timeout_for(deadline)
          @status_timeout_proc.call(deadline)
        end

        private def wifi_interface_airport_data(deadline:)
          data = airport_data(timeout_in_secs: status_timeout_for(deadline))
          iface = status_wifi_interface(deadline)

          AirportDataNavigator.new(data).interface_data(iface)
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
          AirportDataNavigator.placeholder_network_name?(name)
        end
      end
    end
  end
end
