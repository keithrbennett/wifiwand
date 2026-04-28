# frozen_string_literal: true

require 'ipaddr'
require 'shellwords'

require_relative 'base_model'
require_relative '../errors'
require_relative '../mac_helper/mac_os_swift_runtime'
require_relative '../mac_helper/mac_os_wifi_transport'
require_relative '../mac_helper/mac_os_wifi_auth_helper'


module WifiWand
  class MacOsModel < BaseModel
    WIFI_PORT_PATTERNS = [
      /Wi[-\s]?Fi/i,
      /Air[-\s]?Port/i,
      /Wireless/i,
      /WLAN/i,
    ].freeze

    SYSTEM_PROFILER_TIMEOUT_SECONDS = 15
    KEYCHAIN_LOOKUP_TIMEOUT_SECONDS = 5
    SUDO_NETWORKSETUP_TIMEOUT_SECONDS = 5

    # Keychain exit code handlers for password retrieval
    # Exit codes and their meanings:
    # 44  - Item not found in keychain
    # 45  - User denied access to keychain
    # 128 - User cancelled keychain access dialog
    # 51  - Keychain access attempted in non-interactive mode
    # 25  - Invalid keychain search parameters
    # 1   - General error (could be "not found" or other issues)
    KEYCHAIN_EXIT_CODE_HANDLERS = {
      44  => ->(network_name, _error) {}, # Item not found - no password stored
      45  => ->(network_name, _error) { raise KeychainAccessDeniedError, network_name },
      128 => ->(network_name, _error) { raise KeychainAccessCancelledError, network_name },
      51  => ->(network_name, _error) { raise KeychainNonInteractiveError, network_name },
      25  => ->(network_name, _error) {
        raise KeychainError, "Invalid keychain search parameters for network '#{network_name}'"
      },
      1   => ->(network_name, error) {
        if error.text.include?('could not be found')
          nil
        else
          raise KeychainError,
            "Keychain error accessing password for network '#{network_name}': #{error.text.strip}"
        end
      },
    }.freeze

    def fetch_hardware_ports
      output = run_command_using_args(%w[networksetup -listallhardwareports]).stdout

      ports = []
      current = {}

      output.each_line do |line|
        stripped = line.strip
        next if stripped.empty?

        if (match = stripped.match(/^Hardware Port:\s*(.+)$/))
          ports << current if current[:device]
          current = { name: match[1] }
        elsif (match = stripped.match(/^Device:\s*(.+)$/))
          current[:device] = match[1]
        elsif (match = stripped.match(/^Ethernet Address:\s*(.+)$/))
          current[:ethernet_address] = match[1]
        end
      end

      ports << current if current[:device]
      ports
    end

    def find_wifi_port(ports)
      ports.find do |port|
        name = port[:name].to_s
        next false if name.empty?

        WIFI_PORT_PATTERNS.any? { |pattern| pattern.match?(name) }
      end
    end

    def detect_wifi_service_name_from_ports(ports)
      wifi_port = find_wifi_port(ports)
      return wifi_port[:name] if wifi_port && wifi_port[:name] && !wifi_port[:name].empty?

      iface = @wifi_interface
      if iface && !iface.empty?
        match = ports.find { |port| port[:device] == iface && port[:name] && !port[:name].empty? }
        return match[:name] if match
      end

      # Fall back to the common default even if not present in the output
      'Wi-Fi'
    end

    # Lazily detected macOS version to avoid OS calls during initialization
    def macos_version = @macos_version ||= detect_macos_version

    def initialize(options = {})
      super
      # Defer macOS version detection until first needed to minimize incidental OS calls
      @macos_version = nil
      @mac_helper_client = nil
      @swift_runtime = nil
    end

    def connection_ready?(network_name)
      with_airport_data_cache_scope { super }
    end

    def wifi_info
      with_airport_data_cache_scope { super }
    end

    def status_line_data(progress_callback: nil)
      with_airport_data_cache_scope { super }
    end

    def generate_qr_code(filespec = nil, overwrite: false, delivery_mode: :print, password: nil,
      in_stream: $stdin)
      with_airport_data_cache_scope do
        super(filespec, overwrite: overwrite, delivery_mode: delivery_mode, password: password,
          in_stream: in_stream)
      end
    end

    def self.os_id
      :mac
    end

    # Detects the Wi-Fi service name dynamically (e.g., "Wi-Fi", "AirPort", etc.)
    def detect_wifi_service_name
      @detect_wifi_service_name ||= begin
        ports = fetch_hardware_ports
        detect_wifi_service_name_from_ports(ports)
      end
    end

    # Preferred, clearer name for the Wi‑Fi service query.
    # Kept alongside detect_wifi_service_name for backward compatibility.
    def wifi_service_name = detect_wifi_service_name

    # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
    # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
    def detect_wifi_interface_using_networksetup
      ports = fetch_hardware_ports
      service_name = detect_wifi_service_name_from_ports(ports)

      if service_name && !service_name.empty?
        @wifi_service_name = service_name
      end

      wifi_port = ports.find do |port|
        port[:name] == service_name && port[:device] && !port[:device].empty?
      end

      wifi_port ||= find_wifi_port(ports)

      iface = wifi_port && wifi_port[:device]
      raise WifiInterfaceError if iface.nil? || iface.empty?

      iface
    end

    # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
    # Prefer the faster networksetup path and fall back to system_profiler if needed.
    # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
    def probe_wifi_interface
      begin
        iface = detect_wifi_interface_using_networksetup
        return iface if iface && !iface.to_s.empty?
      rescue => _e
        # Fall through to system_profiler fallback
      end

      json_text = run_command_using_args(
        %w[system_profiler -json SPNetworkDataType],
        true,
        timeout_in_secs: SYSTEM_PROFILER_TIMEOUT_SECONDS
      ).stdout
      return nil if json_text.nil? || json_text.strip.empty?

      net_data = JSON.parse(json_text)
      nets = net_data['SPNetworkDataType']

      return nil if nets.nil? || nets.empty?

      detect_wifi_interface_from_profiler_networks(nets)
    end

    # Returns the network names sorted in descending order of signal strength.
    def _available_network_names
      with_airport_data_cache_scope do
        helper_networks = helper_available_network_names
        return helper_networks if helper_networks

        iface = wifi_interface
        data = airport_data

        interfaces = find_airport_interfaces(data)
        return [] unless interfaces

        wifi_data = find_wifi_interface_data(interfaces, iface)
        return [] unless wifi_data

        inner_key = network_list_key(wifi_data)
        networks = wifi_data.fetch(inner_key, [])
        return [] unless networks

        sort_networks_by_signal_strength(networks)
      end
    end

    # Queries available WiFi network names via the macOS helper (CoreWLAN).
    #
    # Returns:
    #   - Array<String> of unique SSID names when the helper returns usable data
    #   - nil when the helper is unavailable, Location Services blocks the
    #     helper, returns no networks, or all SSIDs are filtered placeholders
    #     (signals the caller to try fallback sources)
    #
    # Placeholder SSIDs such as "<hidden>" and "<redacted>" are excluded from
    # the result. All interpretation of the helper response uses the explicit
    # HelperQueryResult returned by scan_networks—no hidden client state is
    # consulted.
    def helper_available_network_names
      result = mac_helper_client.scan_networks
      return nil if result.location_services_blocked?

      networks = result.payload
      return nil unless networks&.any?

      names = networks
        .map { |network| network['ssid'].to_s }
        .reject { |ssid| placeholder_network_name?(ssid) }
        .uniq

      names.empty? ? nil : names
    end

    # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
    def preferred_networks
      iface = wifi_interface
      lines = run_command_using_args(
        ['networksetup', '-listpreferredwirelessnetworks', iface]
      ).stdout.split("\n")
      # Produces something like this, unsorted, and with leading tabs:
      # Preferred networks on en0:
      #         LibraryWiFi
      #         @thePAD/Magma

      lines.delete_at(0)                         # remove title line
      lines.map! { |line| line.gsub("\t", '') }  # remove leading tabs
      lines.sort! { |s1, s2| s1.casecmp(s2) }    # sort alphabetically, case insensitively
      lines
    end

    # Returns whether or not the specified interface is a WiFi interface.
    def is_wifi_interface?(interface)
      run_command_using_args(['networksetup', '-listpreferredwirelessnetworks', interface])
      true  # If command succeeds, it's a WiFi interface
    rescue WifiWand::CommandExecutor::OsCommandError => e
      # Exit code 10 means not a WiFi interface
      if e.exitstatus == 10
        false
      else
        raise
      end
    end

    def wifi_on?
      iface = wifi_interface
      output = run_command_using_args(['networksetup', '-getairportpower', iface]).stdout
      output.chomp.match?(/\): On$/)
    end

    def associated?
      with_airport_data_cache_scope do
        return false unless wifi_on?

        result = mac_helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)

        interface_associated_in_airport_data?(wifi_interface_airport_data)
      end
    rescue WifiWand::Error
      false
    end

    def connected?
      with_airport_data_cache_scope do
        return false unless wifi_on?

        # On Sonoma+, system_profiler may omit spairport_current_network_information
        # entirely when SSID data is redacted. Check the helper first; a real SSID
        # from the helper means the interface is connected even if system_profiler
        # shows nothing.
        result = mac_helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)

        interface_data = wifi_interface_airport_data
        return true if interface_associated_in_airport_data?(interface_data)

        associated_without_ssid?(interface_data)
      end
    end

    # Turns WiFi on.
    def wifi_on
      return if wifi_on?

      invalidate_airport_data_cache

      iface = wifi_interface
      run_command_using_args(['networksetup', '-setairportpower', iface, 'on'])
      wifi_on? ? nil : raise(WifiEnableError)
    end

    # Turns WiFi off.
    def wifi_off
      return unless wifi_on?

      invalidate_airport_data_cache

      iface = wifi_interface
      run_command_using_args(['networksetup', '-setairportpower', iface, 'off'])

      wifi_on? ? raise(WifiDisableError) : nil
    end

    def _connect(network_name, password = nil)
      invalidate_airport_data_cache
      mac_os_wifi_transport.connect(network_name, password)
    end

    # @return:
    #   If the network is in the preferred networks list
    #     If a password is associated w/this network, return the password
    #     If not, return nil
    #   else
    #     raise an error
    def _preferred_network_password(preferred_network_name, timeout_in_secs: KEYCHAIN_LOOKUP_TIMEOUT_SECONDS)
      run_command_using_args(
        [
          'security',
          'find-generic-password',
          '-D',
          'AirPort network password',
          '-a',
          preferred_network_name,
          '-w',
        ],
        true,
        timeout_in_secs: timeout_in_secs
      ).stdout.chomp
    rescue WifiWand::CommandExecutor::OsCommandError => e
      handle_keychain_error(preferred_network_name, e)
    end

    # Returns the IP address assigned to the WiFi interface, or nil if none.

    def _ip_address
      iface = wifi_interface
      run_command_using_args(['ipconfig', 'getifaddr', iface]).stdout.chomp
    rescue WifiWand::CommandExecutor::OsCommandError => e
      if e.exitstatus == 1
        nil
      else
        raise
      end
    end

    def remove_preferred_network(network_name)
      network_name = network_name.to_s
      iface = wifi_interface
      run_command_using_args(
        ['sudo', 'networksetup', '-removepreferredwirelessnetwork', iface, network_name],
        true,
        timeout_in_secs: SUDO_NETWORKSETUP_TIMEOUT_SECONDS
      )
      [network_name]
    end

    # Returns the network currently connected to, or nil if none.

    def connected_network_name
      raise WifiOffError, 'WiFi is off, cannot determine connected network.' unless wifi_on?

      network_name = _connected_network_name
      return network_name if network_name

      if connected? && network_identity_redacted?
        raise MacOsRedactionError.new(
          operation_description: 'Current WiFi network queries',
          reason:                network_identity_redaction_reason
        )
      end

      nil
    end

    def _connected_network_name
      with_airport_data_cache_scope do
        result = mac_helper_client.connected_network_name
        ssid = result.payload
        return ssid if ssid && !placeholder_network_name?(ssid)

        wifi_interface_data = wifi_interface_airport_data

        # Handle interface not found
        return nil unless wifi_interface_data

        # Handle no current network connection
        current_network = wifi_interface_data['spairport_current_network_information']
        return nil unless current_network

        # Return the network name (could still be nil)
        network_name = current_network['_name']
        placeholder_network_name?(network_name) ? nil : network_name
      end
    end

    def network_identity_redacted?
      with_airport_data_cache_scope do
        result = mac_helper_client.connected_network_name
        result.location_services_blocked? || placeholder_network_name?(result.payload)
      end
    rescue WifiWand::Error
      false
    end

    def network_identity_redaction_reason
      return nil unless network_identity_redacted?

      'macOS is redacting WiFi network names until Location Services access is granted'
    end

    def mac_helper_client
      @mac_helper_client ||= WifiWand::MacOsWifiAuthHelper::Client.new(
        out_stream_proc:    -> { out_stream },
        verbose_proc:       -> { verbose? },
        macos_version_proc: -> { macos_version }
      )
    end

    # Disconnects from the currently connected network. Does not turn off WiFi.
    def _disconnect
      invalidate_airport_data_cache
      mac_os_wifi_transport.disconnect
    end

    def mac_address
      iface = wifi_interface
      output = run_command_using_args(['ifconfig', iface]).stdout
      ether_line = output.split("\n").find { |line| line.include?('ether') }
      return nil unless ether_line

      # Extract MAC address (second field after 'ether')
      tokens = ether_line.split
      ether_index = tokens.index('ether')
      ether_index ? tokens[ether_index + 1] : nil
    end

    def set_nameservers(nameservers) # rubocop:disable Naming/AccessorMethodName
      service_name = detect_wifi_service_name

      if nameservers == :clear
        run_command_using_args(['networksetup', '-setdnsservers', service_name, 'empty'])
      else
        # Validate IP addresses (accept both IPv4 and IPv6)
        bad_addresses = nameservers.reject do |ns|
          IPAddr.new(ns)  # Valid if IPAddr can parse it (IPv4 or IPv6)
          true
        rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
          false
        end

        unless bad_addresses.empty?
          raise InvalidIPAddressError, bad_addresses
        end

        run_command_using_args(['networksetup', '-setdnsservers', service_name] + nameservers)
      end

      nameservers
    end

    def open_resource(resource_url) = run_command_using_args(['open', resource_url])

    def nameservers_using_scutil
      output = run_command_using_args(%w[scutil --dns]).stdout
      nameserver_lines = output.split("\n").grep(/^\s*nameserver\[/).uniq
      nameserver_lines.map { |line| line.split(' : ').last.strip }
    end

    def nameservers_using_networksetup
      service_name = detect_wifi_service_name
      output = run_command_using_args(['networksetup', '-getdnsservers', service_name]).stdout
      if output == "There aren't any DNS Servers set on #{service_name}.\n"
        output = ''
      end
      output.split("\n")
    end

    def nameservers = nameservers_using_scutil

    # Returns the network interface used for default internet route on macOS
    def default_interface
      output = run_command_using_args(%w[route -n get default], false).stdout
      return nil if output.empty?

      # Find line containing 'interface:' and extract value
      interface_line = output.split("\n").find { |line| line.include?('interface:') }
      return nil unless interface_line

      interface_line.split.last
    rescue WifiWand::CommandExecutor::OsCommandError
      nil
    end

    # Detects the current macOS version
    def detect_macos_version
      output = run_command_using_args(%w[sw_vers -productVersion]).stdout
      version = output.strip
      version.empty? ? nil : version
    rescue => e
      if verbose?
        out_stream.puts "Could not detect macOS version: #{e.message}."
      end
      nil
    end

    def validate_os_preconditions
      # All core commands are built-in. Eagerly warm the optional
      # Swift/CoreWLAN availability probe here so the runtime owns both the
      # cached result and any targeted verbose diagnostics.
      swift_runtime.swift_and_corewlan_present?

      :ok
    end

    private :detect_wifi_service_name_from_ports,
      :fetch_hardware_ports,
      :find_wifi_port,
      :helper_available_network_names

    private def swift_runtime
      @swift_runtime ||= WifiWand::MacOsSwiftRuntime.new(
        command_runner:  ->(*args, **kwargs) { run_command_using_args(*args, **kwargs) },
        out_stream_proc: -> { out_stream },
        verbose_proc:    -> { verbose? }
      )
    end

    private def mac_os_wifi_transport
      @mac_os_wifi_transport ||= WifiWand::MacOsWifiTransport.new(
        swift_runtime:       swift_runtime,
        command_runner:      ->(*args, **kwargs) { run_command_using_args(*args, **kwargs) },
        wifi_interface_proc: -> { wifi_interface },
        out_stream_proc:     -> { out_stream },
        verbose_proc:        -> { verbose? }
      )
    end

    private def detect_wifi_interface_from_profiler_networks(nets)
      # Reuse the service name learned from the fast path when it is available.
      preferred_service_name = @wifi_service_name
      wifi = if preferred_service_name && !preferred_service_name.empty?
        nets.find { |net| net['_name'] == preferred_service_name }
      end

      # Fall back to an already-known interface if initialization or earlier calls set it.
      wifi ||= if @wifi_interface && !@wifi_interface.empty?
        nets.find { |net| net['interface'] == @wifi_interface }
      end

      # As a last profiler-only heuristic, match common Wi-Fi service names directly.
      wifi ||= nets.find do |net|
        name = net['_name'].to_s
        WIFI_PORT_PATTERNS.any? { |pattern| pattern.match?(name) }
      end

      wifi ? wifi['interface'] : nil
    end

    private def handle_keychain_error(network_name, error)
      handler = KEYCHAIN_EXIT_CODE_HANDLERS[error.exitstatus]

      if handler
        handler.call(network_name, error)
      else
        # Unknown error - provide detailed information for debugging
        error_msg = "Unknown keychain error (exit code #{error.exitstatus}) " \
          "accessing password for network '#{network_name}'"
        error_msg += ": #{error.text.strip}" unless error.text.empty?
        raise KeychainError, error_msg
      end
    end

    # Helper methods for _available_network_names
    private def find_airport_interfaces(data)
      data['SPAirPortDataType']
        &.detect { |h| h.key?('spairport_airport_interfaces') }
        &.fetch('spairport_airport_interfaces', [])
    end

    private def find_wifi_interface_data(interfaces, iface) = interfaces.detect { |h| h['_name'] == iface }

    private def wifi_interface_airport_data
      data = airport_data
      airport_interfaces = data.dig('SPAirPortDataType', 0, 'spairport_airport_interfaces')
      return nil unless airport_interfaces

      iface = wifi_interface
      airport_interfaces.find { |interface| interface['_name'] == iface }
    end

    private def interface_associated_in_airport_data?(wifi_interface_data)
      return false unless wifi_interface_data

      current_network = wifi_interface_data['spairport_current_network_information']
      return true if current_network.is_a?(Hash) && !current_network.empty?
      return true if !current_network.is_a?(Hash) && current_network && !current_network.to_s.empty?

      false
    end

    private def associated_without_ssid?(_wifi_interface_data = nil)
      iface = wifi_interface
      return true if default_interface == iface

      !_ip_address.nil?
    rescue WifiWand::CommandExecutor::OsCommandError
      false
    end

    private def network_list_key(wifi_interface_data = nil)
      associated = if wifi_interface_data
        interface_associated_in_airport_data?(wifi_interface_data)
      else
        connected_network_name
      end

      associated ?
        'spairport_airport_other_local_wireless_networks' :
        'spairport_airport_local_wireless_networks'
    end

    private def sort_networks_by_signal_strength(networks)
      networks
        .sort_by { |net| -extract_signal_strength(net) }
        .map { |h| h['_name'] }
        .reject { |name| placeholder_network_name?(name) }
        .compact
        .uniq
    end

    private def extract_signal_strength(network)
      # 'spairport_signal_noise' is a slash-separated "signal/noise" string (e.g. "-65/-95").
      # Take the first component as the signal strength in dBm; default to "0/0" if absent.
      network.fetch('spairport_signal_noise', '0/0').to_s.split('/').first.to_i
    end

    private def placeholder_network_name?(name)
      value = name.to_s.strip
      value.empty? || %w[<hidden> <redacted>].include?(value.downcase)
    end

    private def with_airport_data_cache_scope
      cache_key = object_id
      outermost_scope = airport_data_cache_depth(cache_key).zero?
      invalidate_airport_data_cache if outermost_scope
      airport_data_cache_depths[cache_key] = airport_data_cache_depth(cache_key) + 1
      yield
    ensure
      next_depth = airport_data_cache_depth(cache_key) - 1

      if next_depth.positive?
        airport_data_cache_depths[cache_key] = next_depth
      else
        airport_data_cache_depths.delete(cache_key)
        invalidate_airport_data_cache
      end
    end

    private def airport_data_cache_depth(cache_key)
      airport_data_cache_depths.fetch(cache_key, 0)
    end

    private def airport_data_cache_depths
      Thread.current[:wifi_wand_airport_data_cache_depths] ||= {}
    end

    private def airport_data_cache_store
      Thread.current[:wifi_wand_airport_data_cache_store] ||= {}
    end

    private def airport_data
      cache_key = object_id
      cached_data = airport_data_cache_store[cache_key]
      return cached_data if cached_data

      json_text = run_command_using_args(
        %w[system_profiler -json SPAirPortDataType],
        true,
        timeout_in_secs: SYSTEM_PROFILER_TIMEOUT_SECONDS
      ).stdout
      begin
        airport_data_cache_store[cache_key] = JSON.parse(json_text)
      rescue JSON::ParserError => e
        raise SystemProfilerError, "Failed to parse system_profiler output: #{e.message}"
      end
    end

    private def invalidate_airport_data_cache
      airport_data_cache_store.delete(object_id)
    end

    # Gets the security type of the currently connected network.
    # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP", or nil if not connected/not found
    private def connection_security_type
      with_airport_data_cache_scope do
        network_name = _connected_network_name
        return nil unless network_name

        data = airport_data
        iface = wifi_interface
        wifi_interface_data = data['SPAirPortDataType']
          &.detect { |h| h.key?('spairport_airport_interfaces') }
          &.dig('spairport_airport_interfaces')
          &.detect { |h| h['_name'] == iface }
        inner_key = network_list_key(wifi_interface_data)

        networks = wifi_interface_data&.dig(inner_key)

        return nil unless networks

        # Find the network we're connected to
        network = networks.detect { |net| net['_name'] == network_name }
        return nil unless network

        # Extract security information
        security_info = network['spairport_security_mode']
        return nil unless security_info

        canonical_security_type_from(security_info)
      end
    end

    # Checks if the currently connected network is a hidden network.
    # A hidden network does not broadcast its SSID.
    # @return [Boolean] true if connected to a hidden network, false otherwise
    private def network_hidden?
      with_airport_data_cache_scope do
        network_name = _connected_network_name
        return false unless network_name

        # Query the connection profile to check if it's marked as hidden
        # On macOS, we can check this via networksetup or by examining if the network
        # appears in the broadcast network list from system_profiler
        data = airport_data
        iface = wifi_interface

        # Get the current network information
        wifi_interface_data = data['SPAirPortDataType']
          &.detect { |h| h.key?('spairport_airport_interfaces') }
          &.dig('spairport_airport_interfaces')
          &.detect { |h| h['_name'] == iface }

        return false unless wifi_interface_data

        # Check if we have current network information
        current_network = wifi_interface_data['spairport_current_network_information']
        return false unless current_network

        # system_profiler does not keep visible SSIDs in one stable array. Once the interface
        # is associated, the current SSID may be moved out of
        # 'spairport_airport_local_wireless_networks' and into
        # 'spairport_airport_other_local_wireless_networks'. If we only inspect the "local"
        # list, a normal visible network can be misclassified as hidden after association.
        #
        # Reuse network_list_key for the primary lookup so this method follows the same
        # associated-network selection rule as connection_security_type, then fall back to
        # checking both lists before concluding that the connected SSID is hidden.
        preferred_networks = wifi_interface_data[network_list_key] || []
        fallback_networks = [
          wifi_interface_data['spairport_airport_local_wireless_networks'],
          wifi_interface_data['spairport_airport_other_local_wireless_networks'],
        ].compact.flatten
        visible_networks = (preferred_networks + fallback_networks).uniq
        network_in_visible_lists = visible_networks.any? { |net| net['_name'] == network_name }

        # If the network we're connected to is not in any visible scan list, it's hidden.
        !network_in_visible_lists
      end
    end

    public :connection_security_type, :network_hidden?
  end
end
