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

    # @!method available_network_names
    #   Returns a list of available Wi-Fi network SSIDs.
    #   @return [Array<String>] A list of network names.

    # @!method connect(network_name, password = nil)
    #   Connects to a Wi-Fi network.
    #   @param network_name [String] The name (SSID) of the network.
    #   @param password [String, nil] The password for the network. (optional)
    #   @return [nil] upon successful connection.
    #   @raise [WifiWand::Error] on failure.

    # @!method connected_network_name
    #   Returns the name of the currently connected network.
    #   @return [String, nil] The SSID of the connected network, or nil if not connected.

    # @!method connected_to?(network_name)
    #   Checks if currently connected to a specific network.
    #   @param network_name [String] The SSID to check against.
    #   @return [Boolean] True if connected to the specified network.

    # @!method connected_to_internet?
    #   Checks for a working internet connection (TCP and DNS).
    #   @return [Boolean] True if the internet is reachable.

    # @!method cycle_network
    #   Turns the Wi-Fi interface off and then on again.
    #   @return [void]

    # @!method default_interface
    #   Returns the default network interface used for routing.
    #   @return [String, nil] The name of the default interface.

    # @!method disconnect
    #   Disconnects from the current Wi-Fi network.
    #   @return [void]

    # @!method dns_working?
    #   Checks if DNS resolution is working.
    #   @return [Boolean] True if DNS is working.

    # @!method generate_qr_code(filespec: nil)
    #   Generates a QR code for the current Wi-Fi connection.
    #   @param filespec [String, nil] The output file path. If nil, a default name is used.
    #     If '-', the QR code is printed to STDOUT.
    #   @return [String] The filename of the generated QR code.
    #   @raise [WifiWand::Error] if not connected or `qrencode` is not installed.

    # @!method internet_tcp_connectivity?
    #   Checks for basic TCP connectivity to the internet.
    #   @return [Boolean] True if TCP connection can be established.

    # @!method ip_address
    #   Returns the IP address of the Wi-Fi interface.
    #   @return [String, nil] The IP address.

    # @!method mac_address
    #   Returns the MAC address of the Wi-Fi interface.
    #   @return [String, nil] The MAC address.

    # @!method nameservers
    #   Returns a list of current DNS nameservers.
    #   @return [Array<String>] A list of nameserver IP addresses.

    # @!method preferred_networks
    #   Returns a list of saved/preferred network SSIDs.
    #   @return [Array<String>] A list of network names.

    # @!method random_mac_address
    #   Generates a random, valid MAC address.
    #   @return [String] The random MAC address.

    # @!method remove_preferred_networks(*network_names)
    #   Removes one or more networks from the preferred/saved list.
    #   @param network_names [String] A list of SSIDs to remove.
    #   @return [void]

    # @!method status_line_data
    #   Returns a hash of the current network status.
    #   @return [Hash] A hash containing status information.

    # @!method wifi_info
    #   Returns a comprehensive hash of all Wi-Fi and network details.
    #   @return [Hash] A hash containing detailed network information.

    # @!method wifi_off
    #   Turns the Wi-Fi interface off.
    #   @return [void]

    # @!method wifi_on
    #   Turns the Wi-Fi interface on.
    #   @return [void]

    # @!method wifi_on?
    #   Checks if the Wi-Fi interface is powered on.
    #   @return [Boolean] True if Wi-Fi is on.

    # Delegate a curated list of methods to the underlying OS-specific model.
    def_delegators :@model, *DELEGATED_METHODS

    # Initializes a new Client.
    #
    # @param options [OpenStruct] optional configuration.
    #   * :verbose (Boolean) - Enable verbose output for debugging.
    #   * :wifi_interface (String) - Specify the Wi-Fi interface to use.
    #   * :out_stream (IO) - Destination for verbose/debug output from the model and its services (defaults to $stdout).
    def initialize(options = OpenStruct.new)
      @model = WifiWand::OperatingSystems.create_model_for_current_os(options)
    rescue NoSupportedOSError
      raise # Re-raise the original error so library consumers can handle it.
    end

    # Gets or sets verbose mode for the underlying model.
    #
    # If called with no argument, returns the current verbose mode.
    # If called with a boolean argument, sets the verbose mode on the model.
    #
    # @param value [Boolean, nil] Optional boolean to enable/disable verbose mode.
    # @return [Boolean] The current verbose mode after any change.
    def verbose_mode(value = :__no_value_provided)
      if value == :__no_value_provided
        @model.verbose_mode
      else
        @model.verbose_mode = !!value
      end
    end

  end
end
