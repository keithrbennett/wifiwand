# frozen_string_literal: true

require 'ipaddr'
require 'ostruct'
require 'shellwords'

require_relative 'base_model'
require_relative '../errors'

module WifiWand

class MacOsModel < BaseModel

  WIFI_PORT_PATTERNS = [
    /Wi[-\s]?Fi/i,
    /Air[-\s]?Port/i,
    /Wireless/i,
    /WLAN/i
  ].freeze

  CONNECTION_FAILURE_PATTERNS = [
    /Failed to join network/i,
    /Error:\s*-3900/,
    /Could not connect/i,
    /Could not find network/i
  ].freeze

  AUTHENTICATION_FAILURE_PATTERNS = [
    /invalid password/i,
    /incorrect password/i,
    /authentication (?:failed|timeout|timed out)/i,
    /802\.1x authentication failed/i,
    /password required/i
  ].freeze

  # Keychain exit code handlers for password retrieval
  # Exit codes and their meanings:
  # 44  - Item not found in keychain
  # 45  - User denied access to keychain
  # 128 - User cancelled keychain access dialog
  # 51  - Keychain access attempted in non-interactive mode
  # 25  - Invalid keychain search parameters
  # 1   - General error (could be "not found" or other issues)
  KEYCHAIN_EXIT_CODE_HANDLERS = {
    44 => ->(network_name, _error) { nil }, # Item not found - no password stored
    45 => ->(network_name, _error) { raise KeychainAccessDeniedError.new(network_name) },
    128 => ->(network_name, _error) { raise KeychainAccessCancelledError.new(network_name) },
    51 => ->(network_name, _error) { raise KeychainNonInteractiveError.new(network_name) },
    25 => ->(network_name, _error) { raise KeychainError.new("Invalid keychain search parameters for network '#{network_name}'") },
    1 => ->(network_name, error) {
      if error.text.include?("could not be found")
        nil
      else
        raise KeychainError.new("Keychain error accessing password for network '#{network_name}': #{error.text.strip}")
      end
    }
  }.freeze

  def fetch_hardware_ports
    output = run_os_command(%w[networksetup -listallhardwareports]).stdout

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
  def macos_version
    @macos_version ||= detect_macos_version
  end

  def initialize(options = {})
    super
    # Defer macOS version detection until first needed to minimize incidental OS calls
    @macos_version = nil
  end

  def self.os_id
    :mac
  end

  # Returns false because fetching the network name on macOS requires system_profiler,
  # which takes 3+ seconds to execute. This makes the status command too slow for
  # interactive use. Users should use the 'info' command when they need the network name.
  def show_network_name_in_status?
    false
  end

  # Detects the Wi-Fi service name dynamically (e.g., "Wi-Fi", "AirPort", etc.)
  def detect_wifi_service_name
    @wifi_service_name ||= begin
      ports = fetch_hardware_ports
      detect_wifi_service_name_from_ports(ports)
    end
  end

  # Preferred, clearer name for the Wi‑Fi service query.
  # Kept alongside detect_wifi_service_name for backward compatibility.
  def wifi_service_name
    detect_wifi_service_name
  end

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
    raise WifiInterfaceError.new if iface.nil? || iface.empty?

    iface
  end

  # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
  # Prefer the faster networksetup path and fall back to system_profiler if needed.
  # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
  def detect_wifi_interface
    begin
      iface = detect_wifi_interface_using_networksetup
      return iface if iface && !iface.to_s.empty?
    rescue => _e
      # Fall through to system_profiler fallback
    end

    json_text = run_os_command(%w[system_profiler -json SPNetworkDataType]).stdout
    return nil if json_text.nil? || json_text.strip.empty?
    net_data = JSON.parse(json_text)
    nets = net_data['SPNetworkDataType']

    return nil if nets.nil? || nets.empty?

    # Use dynamic service name detection
    service_name = detect_wifi_service_name
    wifi = nets.detect { |net| net['_name'] == service_name }

    wifi ? wifi['interface'] : nil
  end

  # Returns the network names sorted in descending order of signal strength.
  def _available_network_names
    iface = ensure_wifi_interface!
    data = airport_data

    interfaces = find_airport_interfaces(data)
    return [] unless interfaces

    wifi_data = find_wifi_interface_data(interfaces, iface)
    return [] unless wifi_data

    inner_key = network_list_key
    networks = wifi_data.fetch(inner_key, [])
    return [] unless networks

    sort_networks_by_signal_strength(networks)
  end


  # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
  def preferred_networks
    iface = ensure_wifi_interface!
    lines = run_os_command(['networksetup', '-listpreferredwirelessnetworks', iface]).stdout.split("\n")
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
    begin
      run_os_command(['networksetup', '-listpreferredwirelessnetworks', interface])
      true  # If command succeeds, it's a WiFi interface
    rescue WifiWand::CommandExecutor::OsCommandError => e
      # Exit code 10 means not a WiFi interface
      e.exitstatus != 10
    end
  end


  # Returns true if WiFi is on, else false.
  def wifi_on?
    iface = ensure_wifi_interface!
    output = run_os_command(['networksetup', '-getairportpower', iface]).stdout
    output.chomp.match?(/\): On$/)
  end


  # Turns WiFi on.
  def wifi_on
    return if wifi_on?

    iface = ensure_wifi_interface!
    run_os_command(['networksetup', '-setairportpower', iface, 'on'])
    wifi_on? ? nil : raise(WifiEnableError.new)
  end


  # Turns WiFi off.
  def wifi_off
    return unless wifi_on?

    iface = ensure_wifi_interface!
    run_os_command(['networksetup', '-setairportpower', iface, 'off'])

    wifi_on? ? raise(WifiDisableError.new) : nil
  end


  # This method is called by BaseModel#connect to do the OS-specific connection logic.
  def os_level_connect_using_networksetup(network_name, password = nil)
    iface = ensure_wifi_interface!
    args = ['networksetup', '-setairportnetwork', iface, network_name]
    args << password if password
    result = run_os_command(args)
    output_text = result.combined_output

    # networksetup returns exit code 0 even on failure, so check output text
    check_connection_result(network_name, output_text)
  end

  def extract_auth_failure_reason(output_text)
    return '' if output_text.nil?

    lines = output_text.lines.map(&:strip).reject(&:empty?)
    filtered = lines.reject { |line| line.match?(/Failed to join network/i) }
    reason = filtered.join(' ')
    reason.empty? ? output_text.strip : reason
  end

  def os_level_connect_using_swift(network_name, password = nil)
    args = [network_name]
    args << password if password
    run_swift_command('WifiNetworkConnector', *args)
  end

  def _connect(network_name, password = nil)
    if swift_and_corewlan_present?
      begin
        os_level_connect_using_swift(network_name, password)
        return
      rescue WifiWand::CommandExecutor::OsCommandError => e
        # Specific error codes that indicate we should try networksetup instead
        # -3900: Generic CoreWLAN error
        # -3905: Network not found via CoreWLAN
        if e.text.include?('code: -3900') || e.text.include?('code: -3905') || e.text.downcase.include?('network not found')
          out_stream.puts "Swift/CoreWLAN failed (#{e.text.strip}). Trying networksetup fallback..." if verbose_mode
        else
          # For other errors, re-raise as they may indicate real problems
          raise
        end
      rescue => e
        out_stream.puts "Swift/CoreWLAN failed: #{e.message}. Trying networksetup fallback..." if verbose_mode
      end
    end

    os_level_connect_using_networksetup(network_name, password)
  end


  # @return:
  #   If the network is in the preferred networks list
  #     If a password is associated w/this network, return the password
  #     If not, return nil
  #   else
  #     raise an error
  def _preferred_network_password(preferred_network_name)
    begin
      return run_os_command(['security', 'find-generic-password', '-D', 'AirPort network password', '-a', preferred_network_name, '-w']).stdout.chomp
    rescue WifiWand::CommandExecutor::OsCommandError => error
      handle_keychain_error(preferred_network_name, error)
    end
  end


  # Returns the IP address assigned to the WiFi interface, or nil if none.
  def _ip_address
    begin
      iface = ensure_wifi_interface!
      run_os_command(['ipconfig', 'getifaddr', iface]).stdout.chomp
    rescue WifiWand::CommandExecutor::OsCommandError => error
      if error.exitstatus == 1
        nil
      else
        raise
      end
    end
  end


  def remove_preferred_network(network_name)
    network_name = network_name.to_s
    iface = ensure_wifi_interface!
    run_os_command(['sudo', 'networksetup', '-removepreferredwirelessnetwork', iface, network_name])
  end


  # Returns the network currently connected to, or nil if none.
  def _connected_network_name
    data = airport_data
    airport_data = data.dig("SPAirPortDataType", 0, "spairport_airport_interfaces")
    return nil unless airport_data

    iface = ensure_wifi_interface!
    wifi_interface_data = airport_data.find do |interface|
      interface["_name"] == iface
    end

    # Handle interface not found
    return nil unless wifi_interface_data

    # Handle no current network connection
    current_network = wifi_interface_data["spairport_current_network_information"]
    return nil unless current_network

    # Return the network name (could still be nil)
    current_network["_name"]
  end


  # Disconnects from the currently connected network. Does not turn off WiFi.
  def _disconnect
    # Try Swift/CoreWLAN first (preferred method)
    if swift_and_corewlan_present?
      begin
        run_swift_command('WifiNetworkDisconnector')
        return nil
      rescue => e
        out_stream.puts "Swift/CoreWLAN disconnect failed: #{e.message}. Falling back to ifconfig..." if verbose_mode
        # Fall through to ifconfig fallback
      end
    else
      out_stream.puts "Swift/CoreWLAN not available. Using ifconfig..." if verbose_mode
    end
    
    # Fallback to ifconfig (disassociate from current network)
    begin
      iface = ensure_wifi_interface!
      run_os_command(['sudo', 'ifconfig', iface, 'disassociate'], false)
    rescue WifiWand::CommandExecutor::OsCommandError
      # If sudo ifconfig fails, try without sudo (may work on some systems)
      run_os_command(['ifconfig', iface, 'disassociate'], false)
    end
    nil
  end


  def mac_address
    iface = ensure_wifi_interface!
    output = run_os_command(['ifconfig', iface]).stdout
    ether_line = output.split("\n").find { |line| line.include?('ether') }
    return nil unless ether_line

    # Extract MAC address (second field after 'ether')
    tokens = ether_line.split
    ether_index = tokens.index('ether')
    ether_index ? tokens[ether_index + 1] : nil
  end


  

  def set_nameservers(nameservers)
    service_name = detect_wifi_service_name

    if nameservers == :clear
      run_os_command(['networksetup', '-setdnsservers', service_name, 'empty'])
    else
      # Validate IP addresses (accept both IPv4 and IPv6)
      bad_addresses = nameservers.reject do |ns|
        begin
          IPAddr.new(ns)  # Valid if IPAddr can parse it (IPv4 or IPv6)
          true
        rescue
          false
        end
      end

      unless bad_addresses.empty?
        raise InvalidIPAddressError.new(bad_addresses)
      end

      run_os_command(['networksetup', '-setdnsservers', service_name] + nameservers)
    end

    nameservers
  end


  def open_application(application_name)
    run_os_command(['open', '-a', application_name])
  end


  def open_resource(resource_url)
    run_os_command(['open', resource_url])
  end


  


  def nameservers_using_scutil
    output = run_os_command(%w[scutil --dns]).stdout
    nameserver_lines = output.split("\n").grep(/^\s*nameserver\[/).uniq
    nameserver_lines.map { |line| line.split(' : ').last.strip }
  end


  def nameservers_using_networksetup
    service_name = detect_wifi_service_name
    output = run_os_command(['networksetup', '-getdnsservers', service_name]).stdout
    if output == "There aren't any DNS Servers set on #{service_name}.\n"
      output = ''
    end
    output.split("\n")
  end

  def nameservers
    # Use scutil for the most accurate DNS information on macOS
    nameservers_using_scutil
  end


  def swift_and_corewlan_present?
    begin
      run_os_command(['swift', '-e', 'import CoreWLAN'], false)
      true
    rescue WifiWand::CommandExecutor::OsCommandError => e
      # Log the specific error if in verbose mode
      if verbose_mode
        case e.exitstatus
        when 127
          out_stream.puts "Swift command not found (exit code #{e.exitstatus}). Install Xcode Command Line Tools."
        when 1
          out_stream.puts "CoreWLAN framework not available (exit code #{e.exitstatus}). Install Xcode."
        else
          out_stream.puts "Swift/CoreWLAN check failed with exit code #{e.exitstatus}: #{e.text.strip}"
        end
      end
      false
    rescue => e
      out_stream.puts "Unexpected error checking Swift/CoreWLAN: #{e.message}" if verbose_mode
      false
    end
  end

  # Returns the network interface used for default internet route on macOS
  def default_interface
    begin
      output = run_os_command(%w[route -n get default], false).stdout
      return nil if output.empty?

      # Find line containing 'interface:' and extract value
      interface_line = output.split("\n").find { |line| line.include?('interface:') }
      return nil unless interface_line

      interface_line.split.last
    rescue WifiWand::CommandExecutor::OsCommandError
      nil
    end
  end


  # Detects the current macOS version
  def detect_macos_version
    begin
      output = run_os_command(%w[sw_vers -productVersion]).stdout
      version = output.strip
      return nil if version.empty?
      version
    rescue => e
      if verbose_mode
        out_stream.puts "Could not detect macOS version: #{e.message}."
      end
      nil
    end
  end

  def validate_os_preconditions
    # All core commands are built-in, just warn about optional ones
    unless command_available?("swift")
      out_stream.puts "Warning: Swift not available. Some advanced features may use fallback methods. Install with: xcode-select --install" if verbose_mode
    end
    
    :ok
  end

  def run_swift_command(basename, *args)
    swift_filespec = File.absolute_path(File.join(File.dirname(__FILE__), "../../../swift/#{basename}.swift"))
    run_os_command(['swift', swift_filespec] + args)
  end

  private :fetch_hardware_ports, :find_wifi_port, :detect_wifi_service_name_from_ports, :extract_auth_failure_reason

  private

  # Helper methods for _preferred_network_password
  def handle_keychain_error(network_name, error)
    handler = KEYCHAIN_EXIT_CODE_HANDLERS[error.exitstatus]

    if handler
      handler.call(network_name, error)
    else
      # Unknown error - provide detailed information for debugging
      error_msg = "Unknown keychain error (exit code #{error.exitstatus}) accessing password for network '#{network_name}'"
      error_msg += ": #{error.text.strip}" unless error.text.empty?
      raise KeychainError.new(error_msg)
    end
  end

  # Helper methods for os_level_connect_using_networksetup
  def check_connection_result(network_name, output_text)
    return unless connection_failed?(output_text)

    if authentication_failed?(output_text)
      reason = extract_auth_failure_reason(output_text)
      raise NetworkAuthenticationError.new(network_name, reason)
    end

    raise WifiWand::CommandExecutor::OsCommandError.new(1, 'networksetup', output_text.strip)
  end

  def connection_failed?(output_text)
    CONNECTION_FAILURE_PATTERNS.any? { |pattern| output_text.match?(pattern) }
  end

  def authentication_failed?(output_text)
    AUTHENTICATION_FAILURE_PATTERNS.any? { |pattern| output_text.match?(pattern) }
  end

  # Helper methods for _available_network_names
  def find_airport_interfaces(data)
    data['SPAirPortDataType']
      &.detect { |h| h.key?('spairport_airport_interfaces') }
      &.fetch('spairport_airport_interfaces', [])
  end

  def find_wifi_interface_data(interfaces, iface)
    interfaces.detect { |h| h['_name'] == iface }
  end

  def network_list_key
    connected_network_name ?
      'spairport_airport_other_local_wireless_networks' :
      'spairport_airport_local_wireless_networks'
  end

  def sort_networks_by_signal_strength(networks)
    networks
      .sort_by { |net| -extract_signal_strength(net) }
      .map { |h| h['_name'] }
      .compact
      .uniq
  end

  def extract_signal_strength(network)
    network.fetch('spairport_signal_noise', '0/0').to_s.split('/').first.to_i
  end

  def airport_data
    json_text = run_os_command(%w[system_profiler -json SPAirPortDataType]).stdout
    begin
      JSON.parse(json_text)
    rescue JSON::ParserError => e
      raise "Failed to parse system_profiler output: #{e.message}"
    end
  end

  # Gets the security type of the currently connected network.
  # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP", or nil if not connected/not found
  def connection_security_type
    network_name = _connected_network_name
    return nil unless network_name

    data = airport_data
    inner_key = 'spairport_airport_local_wireless_networks'

    # Get the networks data from the airport information
    iface = ensure_wifi_interface!
    networks = data['SPAirPortDataType']
         &.detect { |h| h.key?('spairport_airport_interfaces') }
         &.dig('spairport_airport_interfaces')
         &.detect { |h| h['_name'] == iface }
         &.dig(inner_key)

    return nil unless networks

    # Find the network we're connected to
    network = networks.detect { |net| net['_name'] == network_name }
    return nil unless network

    # Extract security information
    security_info = network['spairport_security_mode']
    return nil unless security_info

    canonical_security_type_from(security_info)
  end

    # Checks if the currently connected network is a hidden network.
  # A hidden network does not broadcast its SSID.
  # @return [Boolean] true if connected to a hidden network, false otherwise
  def network_hidden?
    network_name = _connected_network_name
    return false unless network_name

    # Query the connection profile to check if it's marked as hidden
    # On macOS, we can check this via networksetup or by examining if the network
    # appears in the broadcast network list from system_profiler
    data = airport_data
    iface = ensure_wifi_interface!

    # Get the current network information
    wifi_interface_data = data['SPAirPortDataType']
         &.detect { |h| h.key?('spairport_airport_interfaces') }
         &.dig('spairport_airport_interfaces')
         &.detect { |h| h['_name'] == iface }

    return false unless wifi_interface_data

    # Check if we have current network information
    current_network = wifi_interface_data['spairport_current_network_information']
    return false unless current_network

    # On macOS, a network is hidden if it doesn't appear in the broadcast networks list
    # but is still connected. We always check the complete list of visible networks.
    broadcast_networks = wifi_interface_data['spairport_airport_local_wireless_networks'] || []
    network_in_broadcast_list = broadcast_networks.any? { |net| net['_name'] == network_name }

    # If the network we're connected to is not in the broadcast list, it's hidden
    !network_in_broadcast_list
  end

  public :connection_security_type, :network_hidden?
end
end
