# frozen_string_literal: true

module WifiWandSpecSupport
  module Fakes
    class FakeBaseModel < WifiWand::BaseModel
      attr_accessor :wifi_on_state, :available_network_names_state, :connected_network_name_state,
        :connected_state, :ip_address_state, :preferred_network_passwords, :connection_security_type_state,
        :default_interface_state, :mac_address_state, :nameservers_state, :network_hidden_state,
        :preferred_networks_state, :probe_wifi_interface_state, :valid_wifi_interfaces
      attr_reader :connect_calls, :disconnect_calls, :removed_preferred_networks, :power_transitions,
        :wait_until_disassociated_calls

      def self.os_id = :test

      def initialize(options = {})
        super
        @overrides = {}
        @wifi_on_state = true
        @available_network_names_state = %w[TestNetwork1 TestNetwork2]
        @connected_network_name_state = 'TestNetwork1'
        @connected_state = true
        @ip_address_state = '192.168.1.100'
        @preferred_network_passwords = {
          'SavedNetwork1' => 'saved_password',
          'TestNetwork1'  => 'saved_password',
        }
        @connection_security_type_state = 'WPA2'
        @default_interface_state = 'wlan0'
        @mac_address_state = 'aa:bb:cc:dd:ee:ff'
        @nameservers_state = ['8.8.8.8', '8.8.4.4']
        @network_hidden_state = false
        @preferred_networks_state = %w[TestNetwork1 SavedNetwork1]
        @probe_wifi_interface_state = 'wlan0'
        @valid_wifi_interfaces = %w[wlan0 wlan1 en0]
        @connect_calls = []
        @disconnect_calls = []
        @removed_preferred_networks = []
        @power_transitions = []
        @wait_until_disassociated_calls = []
      end

      def set_response(method_name, value = nil, &block)
        @overrides[method_name.to_sym] = block_given? ? block : value
      end

      def clear_response(method_name)
        @overrides.delete(method_name.to_sym)
      end

      def _available_network_names
        evaluate(:available_network_names) { @available_network_names_state }
      end

      def _connected_network_name
        evaluate(:connected_network_name) { @connected_network_name_state }
      end

      def _connect(network_name, password = nil)
        @connect_calls << [network_name, password]
        evaluate(:_connect, network_name, password) do
          @connected_network_name_state = network_name
          @connected_state = true
          nil
        end
      end

      def _disconnect
        @disconnect_calls << true
        evaluate(:_disconnect) do
          @connected_network_name_state = nil
          @connected_state = false
          nil
        end
      end

      def _ip_address
        evaluate(:ip_address) { @ip_address_state }
      end

      def _preferred_network_password(network_name, timeout_in_secs: nil)
        evaluate(:preferred_network_password, network_name, timeout_in_secs: timeout_in_secs) do
          @preferred_network_passwords[network_name]
        end
      end

      def connected?
        evaluate(:connected?) { @connected_state }
      end

      def connection_security_type
        evaluate(:connection_security_type) { @connection_security_type_state }
      end

      def disconnect_stability_window_in_secs
        evaluate(:disconnect_stability_window_in_secs) { super }
      end

      def default_interface
        evaluate(:default_interface) { @default_interface_state }
      end

      def is_wifi_interface?(interface_name)
        evaluate(:is_wifi_interface?, interface_name) { @valid_wifi_interfaces.include?(interface_name) }
      end

      def mac_address
        evaluate(:mac_address) { @mac_address_state }
      end

      def nameservers
        evaluate(:nameservers) { @nameservers_state }
      end

      def network_hidden?
        evaluate(:network_hidden?) { @network_hidden_state }
      end

      def open_resource(_resource) = nil

      def probe_wifi_interface
        evaluate(:probe_wifi_interface) { @probe_wifi_interface_state }
      end

      def preferred_networks
        evaluate(:preferred_networks) { @preferred_networks_state }
      end

      def remove_preferred_network(network_name)
        @removed_preferred_networks << network_name
        evaluate(:remove_preferred_network, network_name) { nil }
      end

      # rubocop:disable Naming/AccessorMethodName
      def set_nameservers(_nameservers) = nil
      # rubocop:enable Naming/AccessorMethodName

      def validate_os_preconditions = nil

      def wifi_off
        @power_transitions << :wifi_off
        return nil unless wifi_on?

        run_command_using_args(%w[test wifi_off])
        @wifi_on_state = false
        till(:wifi_off)
        nil
      end

      def wifi_on
        @power_transitions << :wifi_on
        return nil if wifi_on?

        run_command_using_args(%w[test wifi_on])
        @wifi_on_state = true
        till(:wifi_on)
        nil
      end

      def wifi_on?
        evaluate(:wifi_on?) { @wifi_on_state }
      end

      private def disassociated_stable?
        evaluate(:disassociated_stable?) { super }
      end

      def wait_until_disassociated!(timeout_in_secs:)
        @wait_until_disassociated_calls << timeout_in_secs
        evaluate(:wait_until_disassociated!, timeout_in_secs: timeout_in_secs) { super }
      end

      def evaluate(method_name, *, **)
        value = if @overrides.key?(method_name)
          @overrides[method_name]
        else
          return yield
        end

        value = value.call(self, *, **) if value.respond_to?(:call)
        raise value if value.is_a?(Exception)

        value
      end
    end
  end
end
