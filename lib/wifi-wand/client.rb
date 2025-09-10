require 'forwardable'
require_relative 'errors'
require_relative 'operating_systems'

module WifiWand
  # The Client class provides a simple, high-level interface for interacting
  # with the WifiWand library.
  class Client
    extend Forwardable
    attr_reader :model

    DELEGATED_METHODS = [
      :available_network_names,
      :connect,
      :connected_network_name,
      :connected_to?,
      :connected_to_internet?,
      :cycle_network,
      :default_interface,
      :disconnect,
      :dns_working?,
      :generate_qr_code,
      :internet_tcp_connectivity?,
      :ip_address,
      :mac_address,
      :nameservers,
      :preferred_networks,
      :random_mac_address,
      :remove_preferred_networks,
      :status_line_data,
      :wifi_info,
      :wifi_off,
      :wifi_on,
      :wifi_on?
    ].freeze

    # Delegate a curated list of methods to the underlying OS-specific model.
    def_delegators :@model, *DELEGATED_METHODS

    # Initializes a new Client.
    #
    # @param options [OpenStruct] optional configuration.
    #   * :verbose (Boolean) - Enable verbose output for debugging.
    #   * :wifi_interface (String) - Specify the Wi-Fi interface to use.
    def initialize(options = OpenStruct.new)
      @model = WifiWand::OperatingSystems.create_model_for_current_os(options)
    rescue NoSupportedOSError
      raise # Re-raise the original error so library consumers can handle it.
    end

  end
end
