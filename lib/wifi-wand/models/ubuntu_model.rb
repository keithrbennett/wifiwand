require 'ostruct'

require_relative 'base_model'
require_relative '../errors'

module WifiWand

class UbuntuModel < BaseModel

  def initialize(options = OpenStruct.new)
    super
  end

  def self.os_id
    :ubuntu
  end

  def validate_os_preconditions
    missing_commands = []
    
    # Check for critical commands
    missing_commands << "iw (install: sudo apt install iw)" unless command_available_using_which?("iw")
    missing_commands << "nmcli (install: sudo apt install network-manager)" unless command_available_using_which?("nmcli")
    
    unless missing_commands.empty?
      raise CommandNotFoundError.new(missing_commands)
    end
    
    :ok
  end

  def detect_wifi_interface
    cmd = "iw dev | grep Interface | cut -d' ' -f2"
    interfaces = run_os_command(cmd).split("\n")
    interfaces.first
  end

  def is_wifi_interface?(interface)
    output = run_os_command("iw dev #{Shellwords.shellescape(interface)} info 2>/dev/null", false)
    !output.empty?
  end

  def wifi_on?
    output = run_os_command("nmcli radio wifi", false)
    output.strip == 'enabled'
  end

  def wifi_on
    return if wifi_on?
    run_os_command("nmcli radio wifi on")
    wifi_on? ? nil : raise(WifiEnableError.new)
  end

  def wifi_off
    return unless wifi_on?
    run_os_command("nmcli radio wifi off")
    wifi_on? ? raise(WifiDisableError.new) : nil
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
    # Connect to the Wi-Fi network using nmcli.
    # The 'nmcli dev wifi connect' command handles both new and existing connections.
    # If a password is provided, it will be used (and may update a saved password).
    # If no password is provided, the OS will attempt to use a saved password if available.
    command = "nmcli dev wifi connect #{Shellwords.shellescape(network_name)}"
    command << " password #{Shellwords.shellescape(password)}" if password
    run_os_command(command, false)
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
    
    run_os_command("nmcli connection delete #{Shellwords.shellescape(network_name)}")
    nil
  end

  def os_level_preferred_network_password(preferred_network_name)
    cmd = [
      "nmcli --show-secrets connection show #{Shellwords.shellescape(preferred_network_name)}",
      "grep '802-11-wireless-security.psk:'",
      "cut -d':' -f2-"
    ].join(' | ')
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _ip_address
    cmd = "ip -4 addr show #{Shellwords.shellescape(wifi_interface)} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1"
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.split("\n").first&.strip
  end

  def mac_address
    cmd = "ip link show #{Shellwords.shellescape(wifi_interface)} | grep ether | awk '{print $2}'"
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _disconnect
    interface = wifi_interface
    return nil unless interface
    begin
      run_os_command("nmcli dev disconnect #{Shellwords.shellescape(interface)}")
    rescue WifiWand::CommandExecutor::OsCommandError => e
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
      run_os_command("nmcli connection modify #{Shellwords.shellescape(wifi_interface)} ipv4.dns \"\"", false)
      run_os_command("nmcli connection up #{Shellwords.shellescape(wifi_interface)}", false)
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
        raise InvalidIPAddressError.new(bad_addresses)
      end

      dns_string = nameservers.join(' ')
      # Try to modify the connection, ignore errors if connection doesn't exist
      cmd = "nmcli connection modify #{Shellwords.shellescape(wifi_interface)} ipv4.dns #{Shellwords.shellescape(dns_string)}"
      run_os_command(cmd, false)
      run_os_command("nmcli connection up #{Shellwords.shellescape(wifi_interface)}", false)
    end
    nameservers
  end

  def open_application(application_name)
    run_os_command("xdg-open #{Shellwords.shellescape(application_name)}")
  end

  def open_resource(resource_url)
    run_os_command("xdg-open #{Shellwords.shellescape(resource_url)}")
  end

  # Returns the network interface used for default internet route on Linux
  def default_interface
    begin
      output = run_os_command("ip route show default | awk '{print $5}'", false)
      return nil if output.empty?
      
      # Take the first interface if multiple are returned
      interfaces = output.split("\n").map(&:strip).reject(&:empty?)
      interfaces.first
    rescue WifiWand::CommandExecutor::OsCommandError
      nil
    end
  end

  end
end