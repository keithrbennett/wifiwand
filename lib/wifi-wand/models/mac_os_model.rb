# frozen_string_literal: true

require 'ipaddr'
require 'ostruct'
require 'shellwords'

require_relative 'base_model'
require_relative '../errors'

module WifiWand

class MacOsModel < BaseModel

  # Minimum supported macOS version (Monterey 12.0+)
  # Apple currently supports macOS 12+ as of 2024
  MIN_SUPPORTED_OS_VERSION = "12.0"

  # Lazily detected macOS version to avoid OS calls during initialization
  def macos_version
    @macos_version ||= detect_macos_version
  end

  def initialize(options = OpenStruct.new)
    super
    # Defer macOS version detection until first needed to minimize incidental OS calls
    @macos_version = nil
  end

  def self.os_id
    :mac
  end

  # Detects the Wi-Fi service name dynamically (e.g., "Wi-Fi", "AirPort", etc.)
  def detect_wifi_service_name
    @wifi_service_name ||= begin
      cmd = "networksetup -listallhardwareports"
      lines = run_os_command(cmd).split("\n")
      
      # Look for common Wi-Fi service name patterns
      wifi_patterns = [
        /: Wi-Fi$/,           # Most common
        /: AirPort$/,         # Older systems 
        /: Wireless$/,        # Alternative naming
        /: WiFi$/,            # Alternative spelling
        /: WLAN$/             # Generic wireless LAN
      ]
      
      wifi_service_line = lines.find do |line|
        wifi_patterns.any? { |pattern| pattern.match(line) }
      end
      
      if wifi_service_line
        wifi_service_line.split(': ').last
      else
        # Fallback: look for the interface that matches our wifi_interface
        wifi_iface = wifi_interface
        lines.each_with_index do |line, index|
          if line.include?("Device: #{wifi_iface}") && index > 0
            prev_line = lines[index - 1]
            if prev_line.start_with?("Hardware Port: ")
              return prev_line.split(': ').last
            end
          end
        end
        
        # Final fallback
        "Wi-Fi"
      end
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

    cmd = "networksetup -listallhardwareports"
    lines = run_os_command(cmd).split("\n")
    # Produces something like this:
    # Hardware Port: Wi-Fi
    # Device: en0
    # Ethernet Address: ac:bc:32:b9:a9:9d
    #
    # Hardware Port: Bluetooth PAN
    # Device: en3
    # Ethernet Address: ac:bc:32:b9:a9:9e

    # Use dynamic service name detection instead of hardcoded "Wi-Fi"
    service_name = detect_wifi_service_name
    wifi_interface_line_num = (0...lines.size).detect do |index|
      lines[index].end_with?(": #{service_name}")
    end

    if wifi_interface_line_num.nil?
      raise WifiInterfaceError.new
    else
      lines[wifi_interface_line_num + 1].split(': ').last
    end
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

    cmd = 'system_profiler -json SPNetworkDataType'
    json_text = run_os_command(cmd)
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
    data = airport_data
    inner_key = connected_network_name ? 'spairport_airport_other_local_wireless_networks' : 'spairport_airport_local_wireless_networks'

    nets = data['SPAirPortDataType'] \
       .detect { |h| h.key?('spairport_airport_interfaces') } \
        ['spairport_airport_interfaces'] \
       .detect { |h| h['_name'] == wifi_interface } \
        [inner_key] \
        .sort_by { |net| -net['spairport_signal_noise'].split('/').first.to_i }
    nets.map { |h| h['_name']}.uniq
  end


  # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
  def preferred_networks
    cmd = "networksetup -listpreferredwirelessnetworks #{Shellwords.shellescape(wifi_interface)}"
    lines = run_os_command(cmd).split("\n")
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
    cmd = "networksetup -listpreferredwirelessnetworks #{Shellwords.shellescape(interface)} 2>/dev/null"
    begin
      run_os_command(cmd)
      true  # If command succeeds, it's a WiFi interface
    rescue WifiWand::CommandExecutor::OsCommandError => e
      # Exit code 10 means not a WiFi interface
      e.exitstatus != 10
    end
  end


  # Returns true if WiFi is on, else false.
  def wifi_on?
    cmd = "networksetup -getairportpower #{Shellwords.shellescape(wifi_interface)}"
    output = run_os_command(cmd)
    output.chomp.match?(/\): On$/)
  end


  # Turns WiFi on.
  def wifi_on
    return if wifi_on?

    cmd = "networksetup -setairportpower #{Shellwords.shellescape(wifi_interface)} on"
    run_os_command(cmd)
    wifi_on? ? nil : raise(WifiEnableError.new)
  end


  # Turns WiFi off.
  def wifi_off
    return unless wifi_on?

    cmd = "networksetup -setairportpower #{Shellwords.shellescape(wifi_interface)} off"
    run_os_command(cmd)

    wifi_on? ? raise(WifiDisableError.new) : nil
  end


  # This method is called by BaseModel#connect to do the OS-specific connection logic.
  def os_level_connect_using_networksetup(network_name, password = nil)
    command = "networksetup -setairportnetwork #{Shellwords.shellescape(wifi_interface)} #{Shellwords.shellescape(network_name)}"
    if password
      command << ' ' << Shellwords.shellescape(password)
    end
    run_os_command(command)
  end

  def os_level_connect_using_swift(network_name, password = nil)
    args = [network_name]
    args << password if password
    run_swift_command('WifiNetworkConnector', *args)
  end

  def _connect(network_name, password = nil)
    if swift_and_corewlan_present?
      os_level_connect_using_swift(network_name, password)
    else
      os_level_connect_using_networksetup(network_name, password)
    end
  end


  # @return:
  #   If the network is in the preferred networks list
  #     If a password is associated w/this network, return the password
  #     If not, return nil
  #   else
  #     raise an error
  def _preferred_network_password(preferred_network_name)
    command = %Q{security find-generic-password -D "AirPort network password" -a #{Shellwords.shellescape(preferred_network_name)} -w 2>&1}
    begin
      return run_os_command(command).chomp
    rescue WifiWand::CommandExecutor::OsCommandError => error
      case error.exitstatus
      when 44
        # Item not found in keychain - network has no password stored
        nil
      when 45
        raise KeychainAccessDeniedError.new(preferred_network_name)
      when 128
        raise KeychainAccessCancelledError.new(preferred_network_name)
      when 51
        raise KeychainNonInteractiveError.new(preferred_network_name)
      when 25
        raise KeychainError.new("Invalid keychain search parameters for network '#{preferred_network_name}'")
      when 1
        if error.text.include?("could not be found")
          # Alternative way item not found might be reported
          nil
        else
          raise KeychainError.new("Keychain error accessing password for network '#{preferred_network_name}': #{error.text.strip}")
        end
      else
        # Unknown error - provide detailed information for debugging
        error_msg = "Unknown keychain error (exit code #{error.exitstatus}) accessing password for network '#{preferred_network_name}'"
        error_msg += ": #{error.text.strip}" unless error.text.empty?
        raise KeychainError.new(error_msg)
      end
    end
  end


  # Returns the IP address assigned to the WiFi interface, or nil if none.
  def _ip_address
    begin
      cmd = "ipconfig getifaddr #{Shellwords.shellescape(wifi_interface)}"
      run_os_command(cmd).chomp
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
    cmd = "sudo networksetup -removepreferredwirelessnetwork " + Shellwords.shellescape(wifi_interface) + " " + Shellwords.shellescape(network_name)
    run_os_command(cmd)
  end


  # Returns the network currently connected to, or nil if none.
  def _connected_network_name
    data = airport_data
    airport_data = data.dig("SPAirPortDataType", 0, "spairport_airport_interfaces")
    return nil unless airport_data

    wifi_interface = detect_wifi_interface # e.g. "en0"
    wifi_interface_data = airport_data.find do |interface|
      interface["_name"] == wifi_interface
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
      cmd = "sudo ifconfig #{Shellwords.shellescape(wifi_interface)} disassociate"
      run_os_command(cmd, false)
    rescue WifiWand::CommandExecutor::OsCommandError
      # If sudo ifconfig fails, try without sudo (may work on some systems)
      cmd = "ifconfig #{Shellwords.shellescape(wifi_interface)} disassociate"
      run_os_command(cmd, false)
    end
    nil
  end


  def mac_address
    cmd = "ifconfig #{Shellwords.shellescape(wifi_interface)} | awk '/ether/{print $2}'"
    run_os_command(cmd).chomp
  end


  

  def set_nameservers(nameservers)
    arg = if nameservers == :clear
      'empty'
    else
      bad_addresses = nameservers.reject do |ns|
        begin
          IPAddr.new(ns).ipv4?
          true
        rescue
          false
        end
      end

      unless bad_addresses.empty?
        raise InvalidIPAddressError.new(bad_addresses)
      end
      nameservers.join(' ')
    end # end assignment to arg variable

    cmd = "networksetup -setdnsservers #{Shellwords.shellescape(detect_wifi_service_name)} #{arg}"
    run_os_command(cmd)
    nameservers
  end


  def open_application(application_name)
    cmd = 'open -a ' + Shellwords.shellescape(application_name)
    run_os_command(cmd)
  end


  def open_resource(resource_url)
    cmd = 'open ' + Shellwords.shellescape(resource_url)
    run_os_command(cmd)
  end


  


  def nameservers_using_scutil
    cmd = 'scutil --dns'
    output = run_os_command(cmd)
    nameserver_lines_scoped_and_unscoped = output.split("\n").grep(/^\s*nameserver\[/)
    unique_nameserver_lines = nameserver_lines_scoped_and_unscoped.uniq # take the union
    nameservers = unique_nameserver_lines.map { |line| line.split(' : ').last.strip }
    nameservers
  end


  def nameservers_using_networksetup
    service_name = detect_wifi_service_name
    cmd = "networksetup -getdnsservers #{Shellwords.shellescape(service_name)}"
    output = run_os_command(cmd)
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
      # Try to import CoreWLAN using Swift
      run_os_command("swift -e 'import CoreWLAN'", false)
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
      cmd = "route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}'"
      output = run_os_command(cmd, false)
      return nil if output.empty?
      output.strip
    rescue WifiWand::CommandExecutor::OsCommandError
      nil
    end
  end


  # Detects the current macOS version
  def detect_macos_version
    begin
      cmd = "sw_vers -productVersion"
      output = run_os_command(cmd)
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

  # Validates that the current macOS version is supported
  def validate_macos_version
    version = macos_version
    return unless version
    
    unless supported_version?(version)
      raise UnsupportedSystemError.new("macOS #{MIN_SUPPORTED_OS_VERSION}", version)
    end
    
    out_stream.puts "macOS #{version} detected and supported" if verbose_mode
  end

  # Checks if the current version meets the minimum supported version
  def supported_version?(current_version)
    return false unless current_version

    # Convert to numeric arrays
    version_string_to_num_array = ->(s) { s.split('.').map(&:to_i) }
    current_parts = version_string_to_num_array.(current_version)
    min_parts     = version_string_to_num_array.(MIN_SUPPORTED_OS_VERSION)
    
    # Determine max length for padding
    max_length = [current_parts.length, min_parts.length].max
    
    # Pad array to max_length with zeros
    pad_array = ->(arr) { arr + [0] * (max_length - arr.length) }
    
    (pad_array.(current_parts) <=> pad_array.(min_parts)) >= 0
  end
  private :supported_version?

  def validate_os_preconditions
    # All core commands are built-in, just warn about optional ones
    unless command_available_using_which?("swift")
      out_stream.puts "Warning: Swift not available. Some advanced features may use fallback methods. Install with: xcode-select --install" if verbose_mode
    end
    
    :ok
  end

  def run_swift_command(basename, *args)
    swift_filespec = File.absolute_path(File.join(File.dirname(__FILE__), "../../../swift/#{basename}.swift"))
    escaped_args = args.map { |arg| Shellwords.shellescape(arg) }
    argv = ['swift', swift_filespec] + escaped_args
    command = argv.compact.join(' ')
    run_os_command(command)
  end

  private

  def airport_data
    cmd = 'system_profiler -json SPAirPortDataType'
    json_text = run_os_command(cmd)
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
    networks = data['SPAirPortDataType']
         &.detect { |h| h.key?('spairport_airport_interfaces') }
         &.dig('spairport_airport_interfaces')
         &.detect { |h| h['_name'] == wifi_interface }
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

  public :connection_security_type
end
end
