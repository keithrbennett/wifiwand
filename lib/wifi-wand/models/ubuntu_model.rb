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
    debug_method_entry(__method__)
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
    output.match?(/enabled/)
  end

  def wifi_on
    return if wifi_on?
    run_os_command("nmcli radio wifi on")
    till(:on, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
    wifi_on? ? nil : raise(WifiEnableError.new)
  rescue WifiWand::WaitTimeoutError
    raise WifiEnableError.new
  end

  def wifi_off
    return unless wifi_on?
    run_os_command("nmcli radio wifi off")
    till(:off, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
    wifi_on? ? raise(WifiDisableError.new) : nil
  rescue WifiWand::WaitTimeoutError
    raise WifiDisableError.new
  end

  def _available_network_names
    debug_method_entry(__method__)

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
    debug_method_entry(__method__)
    cmd = %q{nmcli -t -f active,ssid device wifi | egrep '^yes' | cut -d\: -f2}
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _connect(network_name, password = nil)
    #
    # CONNECTION LOGIC
    #
    # This logic is designed to be robust and handle the nuances of nmcli,
    # including the common problem of duplicate connection profiles (e.g.,
    # "MySSID", "MySSID 1").
    #
    # 1. CHECK IF ALREADY CONNECTED:
    #    The first step is to check if we are already connected to the target
    #    network. If so, there's nothing to do.
    #
    # 2. HANDLE CONNECTION REQUESTS WITH A PASSWORD:
    #    If a password is provided, we first check if it's different from the
    #    stored password. We only run a disruptive `modify` command if the
    #    password has actually changed. This prevents unnecessary modifications
    #    during test suite cleanup phases, which can cause system instability.
    #    a. Find the best existing profile for the SSID (by most recent timestamp).
    #    b. If a profile exists and the password differs, query its security type
    #       to use the correct parameter (e.g. .psk, .wep-key0) and modify it.
    #    c. If no profile is found, create a new one from scratch.
    #
    # 3. HANDLE CONNECTION REQUESTS WITHOUT A PASSWORD:
    #    If no password is provided, the user's intent is to connect to a
    #    network that is either open or already saved.
    #    a. Find the best existing profile for the SSID.
    #    b. If a profile is found, attempt to activate it using its stored settings.
    #    c. If no profile is found, assume it's an open network and attempt to connect.

    debug_method_entry(__method__)

    if _connected_network_name == network_name
      return
    end

    begin
      if password
        # Case 2: Password is provided.
        profile = find_best_profile_for_ssid(network_name)
        if profile
          # Profile exists. Only modify it if the password has changed.
          if password != _preferred_network_password(profile)
            security_param = get_security_parameter(network_name)
            if security_param
              modify_cmd = "nmcli connection modify #{Shellwords.shellescape(profile)} #{security_param} #{Shellwords.shellescape(password)}"
              run_os_command(modify_cmd)
            else
              # Fallback if security type can't be determined (e.g. out of range).
              run_os_command("nmcli dev wifi connect #{Shellwords.shellescape(network_name)} password #{Shellwords.shellescape(password)}")
              return # The connect command already activates.
            end
          end
          # Always bring the connection up.
          run_os_command("nmcli connection up #{Shellwords.shellescape(profile)}")
        else
          # No profile exists, create a new one.
          connect_cmd = "nmcli dev wifi connect #{Shellwords.shellescape(network_name)} password #{Shellwords.shellescape(password)}"
          run_os_command(connect_cmd)
        end
      else
        # Case 3: No password provided.
        profile = find_best_profile_for_ssid(network_name)
        if profile
          # Profile exists, try to bring it up with stored settings.
          run_os_command("nmcli connection up #{Shellwords.shellescape(profile)}")
        else
          # No profile exists, try to connect to it as an open network.
          run_os_command("nmcli dev wifi connect #{Shellwords.shellescape(network_name)}")
        end
      end
    rescue WifiWand::CommandExecutor::OsCommandError => e
      # The nmcli command failed. Check if it was because the network was not found.
      if e.message.match?(/No network with SSID/i) || e.message.match?(/Connection activation failed/i)
        raise WifiWand::NetworkNotFoundError.new(network_name)
      else
        # Re-raise the original error if it's for a different reason.
        raise e
      end
    end
  end

  private

  # Determines the correct nmcli security parameter for a given network.
  #
  # @param ssid [String] The SSID of the network to check.
  # @return [String, nil] The nmcli parameter string (e.g., "802-11-wireless-security.psk"),
  #   or nil if the security type cannot be determined or is unsupported.
  def get_security_parameter(ssid)
    debug_method_entry(__method__, binding, :ssid)

    # Use the terse, machine-readable output to get the security protocol.
    cmd = "nmcli -t -f SSID,SECURITY dev wifi list"
    begin
      output = run_os_command(cmd, false)
    rescue WifiWand::CommandExecutor::OsCommandError
      return nil # Can't scan, so can't determine the type.
    end

    network_line = output.split("\n").find { |line| line.start_with?("#{ssid}:") }
    return nil unless network_line

    # The output can be like "SSID:WPA2" or "SSID:WPA1 WPA2", so we just grab the part after the first colon.
    security_type = network_line.split(':')[1..-1].join(':').strip

    case canonical_security_type_from(security_type)
    when 'WPA3', 'WPA2', 'WPA'
      "802-11-wireless-security.psk"
    when 'WEP'
      "802-11-wireless-security.wep-key0"
    else
      # Unsupported, enterprise, or open network (shouldn't need password).
      nil
    end
  end

  # Preferred, clearer name for security parameter query
  def security_parameter(ssid)
    get_security_parameter(ssid)
  end

  # Finds the best connection profile for a given SSID.
  # "Best" is defined as the one with the most recent TIMESTAMP, which indicates
  # it was the most recently used or configured. This helps solve the problem
  # of duplicate connection names (e.g., "MySSID", "MySSID 1").
  #
  # @param ssid [String] The SSID to search for.
  # @return [String, nil] The name of the best profile, or nil if none are found.
  def find_best_profile_for_ssid(ssid)
    # Get all profiles for the SSID, with their name and timestamp.
    # The output is a colon-separated string, e.g., "MySSID:1678886400"
    debug_method_entry(__method__, binding, :ssid)

    cmd = "nmcli -t -f NAME,TIMESTAMP connection show"
    begin
      output = run_os_command(cmd, false)
    rescue WifiWand::CommandExecutor::OsCommandError
      # If the command fails for any reason, we can't find profiles.
      return nil
    end

    profiles = output.split("\n").map do |line|
      name, timestamp = line.split(':')
      # We only care about profiles whose names start with the SSID,
      # to catch "MySSID" and "MySSID 1", etc.
      if name.start_with?(ssid)
        { name: name, timestamp: timestamp.to_i }
      else
        nil
      end
    end.compact

    # Find the profile with the highest (most recent) timestamp.
    profiles.max_by { |p| p[:timestamp] }&.dig(:name)
  end

  public

  def remove_preferred_network(network_name)
    puts "Entered #{self.class}##{__method__} with #{network_name}" if verbose_mode

    # Check if the network exists first
    existing_networks = preferred_networks
    return nil unless existing_networks.include?(network_name)
    
    run_os_command("nmcli connection delete #{Shellwords.shellescape(network_name)}")
    nil
  end

  def preferred_networks
    debug_method_entry(__method__)

    output = run_os_command("nmcli -t -f NAME connection show")
    connections = output.split("\n").map(&:strip).reject(&:empty?)
    connections.sort
  end

  def _preferred_network_password(preferred_network_name)
    debug_method_entry(__method__, binding, :preferred_network_name)

    cmd = [
      "nmcli --show-secrets connection show #{Shellwords.shellescape(preferred_network_name)}",
      "grep '802-11-wireless-security.psk:'",
      "cut -d':' -f2-"
    ].join(' | ')
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _ip_address
    debug_method_entry(__method__)

    cmd = "ip -4 addr show #{Shellwords.shellescape(wifi_interface)} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1"
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.split("\n").first&.strip
  end

  def mac_address
  # def mac_address(new_mac_address = nil)
  #   if new_mac_address
  #     raise InvalidMacAddressError.new(new_mac_address) unless valid_mac_address?(new_mac_address)
  #     run_os_command("sudo ip link set dev #{Shellwords.shellescape(wifi_interface)} down")
  #     run_os_command("sudo ip link set dev #{Shellwords.shellescape(wifi_interface)} address #{Shellwords.shellescape(new_mac_address)}")
  #     run_os_command("sudo ip link set dev #{Shellwords.shellescape(wifi_interface)} up")
  #   end
    debug_method_entry(__method__)

    cmd = "ip link show #{Shellwords.shellescape(wifi_interface)} | grep ether | awk '{print $2}'"
    output = run_os_command(cmd, false)
    output.empty? ? nil : output.strip
  end

  def _disconnect
    debug_method_entry(__method__)

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
    debug_method_entry(__method__)
    
    # First try to get DNS from the active connection profile
    # This shows the configured DNS for the current Wi-Fi network
    current_connection = _connected_network_name
    if current_connection
      connection_nameservers = nameservers_from_connection(current_connection)
      return connection_nameservers unless connection_nameservers.empty?
    end
    
    # Fallback to system resolver if no connection-specific DNS
    nameservers_using_resolv_conf || []
  end

  def set_nameservers(nameservers)
    # Use NetworkManager connection-based DNS configuration
    # This is the correct approach for Ubuntu - we modify the connection profile,
    # not the interface directly. Each Wi-Fi network has its own connection profile
    # which can have different DNS settings.

    debug_method_entry(__method__, binding, :nameservers)

    # Get the current active Wi-Fi connection name
    current_connection = _connected_network_name
    raise WifiInterfaceError.new("No active Wi-Fi connection to configure DNS for.") unless current_connection

    if nameservers == :clear
      # Clear custom DNS and use automatic DNS from router/DHCP
      run_os_command("nmcli connection modify #{Shellwords.shellescape(current_connection)} ipv4.dns \"\"", false)
      run_os_command("nmcli connection modify #{Shellwords.shellescape(current_connection)} ipv4.ignore-auto-dns no", false)
    else
      # Validate IP addresses
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

      # Set custom DNS servers and ignore automatic DNS from router/DHCP
      dns_string = nameservers.join(' ')
      run_os_command("nmcli connection modify #{Shellwords.shellescape(current_connection)} ipv4.dns \"#{dns_string}\"", false)
      run_os_command("nmcli connection modify #{Shellwords.shellescape(current_connection)} ipv4.ignore-auto-dns yes", false)
    end
    
    # Restart the connection to apply DNS changes
    run_os_command("nmcli connection up #{Shellwords.shellescape(current_connection)}", false)
    
    nameservers
  end

  def open_resource(resource_url)
    debug_method_entry(__method__, binding, :resource_url)

    run_os_command("xdg-open #{Shellwords.shellescape(resource_url)}")
  end

  # Returns the network interface used for default internet route on Linux
  def default_interface
    debug_method_entry(__method__)

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

  # Gets DNS nameservers configured for a specific connection profile
  # This is the NetworkManager connection-based approach for getting DNS
  def nameservers_from_connection(connection_name)
    debug_method_entry(__method__, binding, :connection_name)
    
    begin
      output = run_os_command("nmcli connection show #{Shellwords.shellescape(connection_name)}", false)
      
      # Extract DNS servers from connection configuration
      # Look for both static configuration (ipv4.dns[1]:) and active DNS (IP4.DNS[1]:)
      # Format examples:
      #   ipv4.dns[1]:                        1.1.1.1    (manually configured)
      #   IP4.DNS[1]:                         192.168.3.1 (from DHCP/router)
      dns_lines = output.split("\n").select do |line|
        line.match?(/ip4\.dns\[\d+\]:/i)
      end
      
      nameservers = dns_lines.map do |line|
        # Split on colon and take everything after the last colon, then strip whitespace
        line.split(':').last.strip
      end.reject(&:empty?)
      
      nameservers
    rescue WifiWand::CommandExecutor::OsCommandError
      # If we can't get connection info, return empty array
      []
    end
  end

  # Gets nameservers from /etc/resolv.conf - fallback method
  def nameservers_using_resolv_conf
    begin
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end
  end

  # Gets the security type of the currently connected network.
  # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP", "None", or nil if not connected/not found
  def connection_security_type
    debug_method_entry(__method__)
    
    network_name = _connected_network_name
    return nil unless network_name
    
    # Use the terse, machine-readable output to get the security protocol.
    cmd = "nmcli -t -f SSID,SECURITY dev wifi list"
    begin
      output = run_os_command(cmd, false)
    rescue WifiWand::CommandExecutor::OsCommandError
      return nil # Can't scan, return nil
    end

    network_line = output.split("\n").find { |line| line.start_with?("#{network_name}:") }
    return nil unless network_line

    # The output can be like "SSID:WPA2" or "SSID:WPA1 WPA2", so we just grab the part after the first colon.
    security_type = network_line.split(':')[1..-1].join(':').strip

    # Normalize via shared logic (returns nil for open/enterprise/unknown)
    canonical_security_type_from(security_type)
  end

  end
end
