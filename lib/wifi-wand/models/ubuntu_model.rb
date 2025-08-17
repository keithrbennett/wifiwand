require 'ostruct'

require_relative 'base_model'
require_relative '../error'

module WifiWand

class UbuntuModel < BaseModel

  def initialize(options = OpenStruct.new)
    super
  end

  def detect_wifi_interface
    interfaces = run_os_command("iw dev | grep Interface | cut -d' ' -f2").split("\n")
    interfaces.first
  end

  def is_wifi_interface?(interface)
    output = run_os_command("iw dev #{interface} info 2>/dev/null", false)
    !output.empty?
  end

  def wifi_on?
    output = run_os_command("nmcli radio wifi", false)
    output.strip == 'enabled'
  end

  def wifi_on
    return if wifi_on?
    run_os_command("nmcli radio wifi on")
    wifi_on? ? nil : raise(Error.new("Wifi could not be enabled."))
  end

  def wifi_off
    return unless wifi_on?
    run_os_command("nmcli radio wifi off")
    wifi_on? ? raise(Error.new("Wifi could not be disabled.")) : nil
  end

  def _available_network_names
    
    output = run_os_command("nmcli -t -f SSID,SIGNAL dev wifi list")
    networks_with_signal = output.split("\n").map(&:strip).reject(&:empty?)
    
    # Parse SSID and signal strength, then sort by signal (descending)
    networks = networks_with_signal.map do |line|
      ssid, signal = line.split(':')
      [ssid, signal.to_i]
    end.sort_by { |_, signal| -signal }.map { |ssid, _| ssid }
    
    networks.uniq
  end

  def _connected_network_name
    cmd = "nmcli -t -f NAME,TYPE connection show --active | grep 802-11-wireless | cut -d: -f1"
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _connect(network_name, password = nil)
    # Check if there's an existing connection profile for this network
    existing_connections = preferred_networks
    if existing_connections.include?(network_name)
      # Use exact matching with existing connection
      run_os_command("nmcli connection up '#{network_name}'")
    else
      # Create new connection - use BSSID for exact matching to avoid substring issues
      # First get the available networks and find the exact match
      available_networks_output = run_os_command("nmcli -t -f SSID,BSSID dev wifi list")
      networks = available_networks_output.split("\n").map do |line|
        # Handle escaped colons in BSSID - split on first unescaped colon only
        if line =~ /^(.+?):(.+)$/
          ssid = $1
          bssid = $2.gsub('\\:', ':')  # Unescape the colons in BSSID
          [ssid.strip, bssid.strip] unless ssid.empty? || bssid.empty?
        end
      end.compact
      
      # Find exact match for SSID
      exact_match = networks.find { |ssid, _| ssid == network_name }
      
      if exact_match
        ssid, bssid = exact_match
        if password
          run_os_command("nmcli dev wifi connect '#{ssid}' password '#{password}' bssid '#{bssid}'")
        else
          run_os_command("nmcli dev wifi connect '#{ssid}' bssid '#{bssid}'")
        end
      else
        raise Error.new("Network '#{network_name}' not found in available networks.")
      end
    end
  end

  def preferred_networks
    output = run_os_command("nmcli -t -f NAME connection show")
    connections = output.split("\n").map(&:strip).reject(&:empty?)
    connections.sort
  end

  def remove_preferred_network(network_name)
    # Check if the network exists first
    existing_networks = preferred_networks
    return nil unless existing_networks.include?(network_name)
    
    run_os_command("nmcli connection delete '#{network_name}'")
    nil
  end

  def os_level_preferred_network_password(preferred_network_name)
    cmd = [
      "nmcli --show-secrets connection show '#{preferred_network_name}'",
      "grep '802-11-wireless-security.psk:'",
      "cut -d':' -f2-"
    ].join(' | ')
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _ip_address
    output = run_os_command("ip -4 addr show #{wifi_interface} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1", false)
    output.empty? ? nil : output.split("\n").first&.strip
  end

  def mac_address
    output = run_os_command("ip link show #{wifi_interface} | grep ether | awk '{print $2}'", false)
    output.empty? ? nil : output.strip
  end

  def _disconnect
    interface = wifi_interface
    return nil unless interface
    begin
      run_os_command("nmcli dev disconnect #{interface}")
    rescue OsCommandError => e
      # It's normal for disconnect to fail if there's no active connection
      # Common scenarios: device not active, not connected to any network
      return nil if e.exitstatus == 6
      raise e
    end
    nil
  end

  def nameservers
    nameservers_using_resolv_conf
  end

  def set_nameservers(nameservers)
    # For setting nameservers, we'll use a different approach
    # Since nmcli connection management requires specific connection names,
    # we'll modify the system's DNS configuration directly
    
    if nameservers == :clear
      # Clear nameservers by removing custom DNS configuration
      run_os_command("nmcli connection modify '#{wifi_interface}' ipv4.dns \"\"", false)
      run_os_command("nmcli connection up '#{wifi_interface}'", false)
    else
      bad_addresses = nameservers.reject do |ns|
        begin
          require 'ipaddr'
          IPAddr.new(ns).ipv4?
          true
        rescue => e
          puts e
          false
        end
      end

      unless bad_addresses.empty?
        raise Error.new("Bad IP addresses provided: #{bad_addresses.join(', ')}")
      end

      dns_string = nameservers.join(' ')
      # Try to modify the connection, ignore errors if connection doesn't exist
      run_os_command("nmcli connection modify '#{wifi_interface}' ipv4.dns '#{dns_string}'", false)
      run_os_command("nmcli connection up '#{wifi_interface}'", false)
    end
    nameservers
  end

  def open_application(application_name)
    run_os_command("xdg-open '#{application_name}'")
  end

  def open_resource(resource_url)
    run_os_command("xdg-open '#{resource_url}'")
  end

  # Returns the network interface used for default internet route on Linux
  def default_interface
    begin
      output = run_os_command("ip route show default | awk '{print $5}'", false)
      return nil if output.empty?
      
      # Take the first interface if multiple are returned
      interfaces = output.split("\n").map(&:strip).reject(&:empty?)
      interfaces.first
    rescue OsCommandError
      nil
    end
  end

  end
end