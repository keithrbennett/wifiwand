# frozen_string_literal: true

require_relative 'airport_data_navigator'
require_relative 'colon_output_parser'
require_relative 'connected_network_flag_context'
require_relative '../../errors'
require_relative '../../string_predicates'
require_relative '../../services/command_executor'

module WifiWand
  class MacOsNetworkIdentityReader
    include MacOsConnectedNetworkFlagContext
    include MacOsColonOutputParser
    include StringPredicates

    NO_CONNECTED_NETWORK = Object.new.freeze

    def initialize(
      helper_client_proc:,
      command_runner:,
      airport_data_proc:,
      airport_data_cache_scope_proc:,
      wifi_on_proc:,
      wifi_interface_proc:,
      default_interface_proc:,
      ip_address_proc:,
      airport_command:
    )
      @helper_client_proc = helper_client_proc
      @command_runner = command_runner
      @airport_data_proc = airport_data_proc
      @airport_data_cache_scope_proc = airport_data_cache_scope_proc
      @wifi_on_proc = wifi_on_proc
      @wifi_interface_proc = wifi_interface_proc
      @default_interface_proc = default_interface_proc
      @ip_address_proc = ip_address_proc
      @airport_command = airport_command
    end

    def associated?
      with_airport_data_cache_scope do
        return false unless wifi_on?

        result = helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)
        return false if result.not_connected?

        interface_associated_in_airport_data?(wifi_interface_airport_data)
      end
    rescue WifiWand::Error
      false
    end

    def connected?
      with_airport_data_cache_scope do
        return false unless wifi_on?

        result = helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)
        return false if result.not_connected?

        interface_data = wifi_interface_airport_data
        return true if interface_associated_in_airport_data?(interface_data)

        associated_without_ssid?(interface_data)
      end
    end

    def connected_network_name
      raise WifiOffError, 'WiFi is off, cannot determine connected network.' unless wifi_on?

      with_connected_network_flag_scope do
        with_airport_data_cache_scope do
          network_name = connected_network_name_raw
          return network_name if network_name
          return nil if connected_network_authoritatively_disconnected?

          if connected? && network_identity_redacted?
            raise MacOsRedactionError.new(
              operation_description: 'Current WiFi network queries',
              reason:                network_identity_redaction_reason
            )
          end

          nil
        end
      end
    end

    def connected_network_name_raw
      network_name = connected_network_name_candidate
      return mark_connected_network_authoritatively_disconnected if no_connected_network?(network_name)

      network_name
    end

    private def connected_network_name_candidate
      with_airport_data_cache_scope do
        result = helper_client.connected_network_name
        ssid = result.payload
        return ssid if ssid && !placeholder_network_name?(ssid)
        return nil if result.not_connected?

        fast_network_name = network_name_using_fast_commands
        return fast_network_name if no_connected_network?(fast_network_name)
        return fast_network_name if fast_network_name

        wifi_interface_data = wifi_interface_airport_data
        return nil unless wifi_interface_data
        return nil unless MacOsAirportDataNavigator.current_network_present?(wifi_interface_data)

        network_name = MacOsAirportDataNavigator.current_network_name(
          wifi_interface_data,
          include_placeholder: true
        )
        return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

        network_name
      end
    end

    def network_identity_redacted?
      return true if connected_network_fallback_identity_redacted?

      with_airport_data_cache_scope do
        result = helper_client.connected_network_name
        result.location_services_error? ||
          helper_placeholder_network_name?(result.payload) ||
          fallback_network_identity_missing?
      end
    rescue WifiWand::Error
      false
    end

    def network_identity_redaction_reason
      return nil unless network_identity_redacted?

      'macOS is redacting WiFi network names until Location Services access is granted ' \
        'to wifiwand-helper, the macOS helper application'
    end

    private def network_name_using_fast_commands(timeout_in_secs: nil)
      network_name = connected_network_name_using_networksetup(timeout_in_secs: timeout_in_secs)
      return network_name if network_name

      connected_network_name_using_airport(timeout_in_secs: timeout_in_secs)
    end

    private def connected_network_name_using_networksetup(iface: wifi_interface, timeout_in_secs: nil)
      output = command_runner.call(
        ['networksetup', '-getairportnetwork', iface],
        timeout_in_secs: timeout_in_secs
      ).stdout.strip
      return nil if output.empty?
      return NO_CONNECTED_NETWORK if output.match?(/not associated|power is currently off/i)

      match = output.match(/\ACurrent (?:Wi-Fi|AirPort) Network:\s*(.*)\z/)
      return nil unless match

      network_name = match[1].strip
      return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

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
      if airport_info.key?('SSID')
        return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

        return network_name
      end

      mark_connected_network_fallback_identity_redacted if airport_info['BSSID']
      nil
    rescue WifiWand::Error
      nil
    end

    private def no_connected_network?(network_name)
      network_name.equal?(NO_CONNECTED_NETWORK)
    end

    private def fallback_network_identity_missing?
      wifi_interface_data = wifi_interface_airport_data
      return false if MacOsAirportDataNavigator.current_network_present?(wifi_interface_data)

      associated_without_ssid?(wifi_interface_data)
    end

    private def helper_placeholder_network_name?(network_name)
      !network_name.nil? && placeholder_network_name?(network_name)
    end

    private def associated_without_ssid?(_wifi_interface_data = nil)
      iface = wifi_interface
      return true if default_interface == iface

      !ip_address.nil?
    rescue WifiWand::CommandExecutor::OsCommandError
      false
    end

    private def interface_associated_in_airport_data?(wifi_interface_data)
      MacOsAirportDataNavigator.associated?(wifi_interface_data)
    end

    private attr_reader :command_runner

    private def helper_client
      @helper_client_proc.call
    end

    private def with_airport_data_cache_scope(&)
      @airport_data_cache_scope_proc.call(&)
    end

    private def airport_data(timeout_in_secs: nil)
      @airport_data_proc.call(timeout_in_secs: timeout_in_secs)
    end

    private def wifi_on?
      @wifi_on_proc.call
    end

    private def wifi_interface
      @wifi_interface_proc.call
    end

    private def default_interface
      @default_interface_proc.call
    end

    private def ip_address
      @ip_address_proc.call
    end

    private def wifi_interface_airport_data(timeout_in_secs: nil)
      data = airport_data(timeout_in_secs: timeout_in_secs)
      iface = wifi_interface

      MacOsAirportDataNavigator.new(data).interface_data(iface)
    end

    private def placeholder_network_name?(name)
      MacOsAirportDataNavigator.placeholder_network_name?(name)
    end
  end
end
