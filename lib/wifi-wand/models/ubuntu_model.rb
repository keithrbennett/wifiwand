require 'ostruct'

require_relative 'base_model'
require_relative '../error'

module WifiWand

class UbuntuModel < BaseModel

  def initialize(options = OpenStruct.new)
    super
  end

  def detect_wifi_interface
    interfaces = run_os_command("iw dev | awk '$1==\"Interface\"{print $2}'").split("\n")
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

  def available_network_names
    return nil unless wifi_on?
    
    output = run_os_command("nmcli -t -f SSID dev wifi list")
    networks = output.split("\n").map(&:strip).reject(&:empty?).uniq
    networks.sort
  end

  def connected_network_name
    return nil unless wifi_on?
    
    output = run_os_command("nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2", false)
    output.empty? ? nil : output.strip
  end

  def os_level_connect(network_name, password = nil)
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
    run_os_command("nmcli connection delete '#{network_name}'")
  end

  def os_level_preferred_network_password(preferred_network_name)
    output = run_os_command("nmcli --show-secrets connection show '#{preferred_network_name}' | grep '802-11-wireless-security.psk:' | cut -d':' -f2- | sed 's/^[[:space:]]*//'", false)
    output.empty? ? nil : output.strip
  end

  def ip_address
    return nil unless wifi_on?
    
    output = run_os_command("ip -4 addr show #{wifi_interface} | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'", false)
    output.empty? ? nil : output.strip
  end

  def mac_address
    output = run_os_command("ip link show #{wifi_interface} | grep -oP '(?<=ether\\s)[0-9a-f:]{17}'", false)
    output.empty? ? nil : output.strip
  end

  def disconnect
    return nil unless wifi_on?
    run_os_command("nmcli dev disconnect #{wifi_interface}")
    nil
  end

  def nameservers
    nameservers_using_resolv_conf
  end

  def set_nameservers(nameservers)
    if nameservers == :clear
      run_os_command("nmcli connection modify '#{wifi_interface}' ipv4.dns \"\"")
      run_os_command("nmcli connection up '#{wifi_interface}'")
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
      run_os_command("nmcli connection modify '#{wifi_interface}' ipv4.dns '#{dns_string}'")
      run_os_command("nmcli connection up '#{wifi_interface}'")
    end
    nameservers
  end

  def open_application(application_name)
    run_os_command("xdg-open '#{application_name}'")
  end

  def open_resource(resource_url)
    run_os_command("xdg-open '#{resource_url}'")
  end

  def wifi_info
    connected = begin
      connected_to_internet?
    rescue
      false
    end

    info = {
        'wifi_on'     => wifi_on?,
        'internet_on' => connected,
        'interface'   => wifi_interface,
        'network'     => connected_network_name,
        'ip_address'  => ip_address,
        'mac_address' => mac_address,
        'nameservers' => nameservers,
        'timestamp'   => Time.now,
    }

    if info['internet_on']
      begin
        info['public_ip'] = public_ip_address_info
      rescue => e
        puts <<~MESSAGE
          #{e.class} obtaining public IP address info, proceeding with everything else. Error message:
          #{e}

        MESSAGE
      end
    end
    info
  end
end
end