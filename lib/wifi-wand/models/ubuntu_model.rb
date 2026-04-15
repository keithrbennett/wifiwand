# frozen_string_literal: true

require 'ostruct'

require_relative 'base_model'
require_relative '../errors'

module WifiWand
  class UbuntuModel < BaseModel
    PREFERRED_NETWORK_SECRET_FIELDS = %w[
      802-11-wireless-security.psk
      802-11-wireless-security.wep-key0
    ].freeze

    def initialize(options = {}) = super

    def self.os_id
      :ubuntu
    end

    def validate_os_preconditions
      missing_commands = []

      # Check for critical commands
      missing_commands << 'iw (install: sudo apt install iw)' unless command_available?('iw')
      unless command_available?('nmcli')
        missing_commands << 'nmcli (install: sudo apt install network-manager)'
      end


      unless missing_commands.empty?
        raise CommandNotFoundError, missing_commands
      end

      :ok
    end

    def probe_wifi_interface
      debug_method_entry(__method__)
      lines = run_os_command(%w[iw dev]).stdout.lines.map(&:strip)
      current_interface = nil
      lines.each do |line|
        if line.start_with?('Interface ')
          current_interface = line.split[1]
        elsif line.start_with?('type managed') && current_interface
          return current_interface
        end
      end
      nil
    end

    def is_wifi_interface?(interface)
      # Redirect stderr to /dev/null - requires shell
      output = run_os_command("iw dev #{Shellwords.shellescape(interface)} info 2>/dev/null", false).stdout
      !output.empty?
    end

    def wifi_on?
      output = run_os_command(%w[nmcli radio wifi], false).stdout
      output.match?(/enabled/)
    end

    def connected?
      return false unless wifi_on?

      iface = wifi_interface
      output = run_os_command(%w[nmcli -t -f DEVICE connection show --active], false).stdout
      output.split("\n").any? { |line| line.strip == iface }
    end

    def connection_ready?(network_name)
      return false unless _connected_network_name == network_name
      return false if active_connection_profile_name.nil?
      return false unless connected?

      true
    rescue WifiWand::Error => e
      out_stream.puts("connection_ready? check failed: #{e.class}: #{e.message}") if @verbose_mode
      false
    end

    def wifi_on
      return if wifi_on?

      run_os_command(%w[nmcli radio wifi on])
      till(:wifi_on, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      wifi_on? ? nil : raise(WifiEnableError)
    rescue WifiWand::WaitTimeoutError
      raise WifiEnableError
    end

    def wifi_off
      return unless wifi_on?

      run_os_command(%w[nmcli radio wifi off])
      till(:wifi_off, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      wifi_on? ? raise(WifiDisableError) : nil
    rescue WifiWand::WaitTimeoutError
      raise WifiDisableError
    end

    def _available_network_names
      debug_method_entry(__method__)

      output = run_os_command(['nmcli', '-t', '-f', 'SSID,SIGNAL', 'dev', 'wifi', 'list']).stdout
      networks_with_signal = output.split("\n").map(&:strip).reject(&:empty?)

      # Parse SSID and signal strength, then sort by signal (descending)
      networks = networks_with_signal.map do |line|
        ssid, signal = nmcli_split(line, 2)
        [ssid, signal.to_i]
      end.sort_by { |_, signal| -signal }.map { |ssid, _| ssid }.reject(&:empty?)

      networks.uniq
    end

    def _connected_network_name
      debug_method_entry(__method__)
      output = run_os_command(['nmcli', '-t', '-f', 'active,ssid', 'device', 'wifi'], false).stdout
      active_line = output.split("\n").find { |line| nmcli_split(line, 2).first == 'yes' }
      return nil unless active_line

      nmcli_split(active_line, 2).last&.strip
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

      if connected? && _connected_network_name == network_name
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
                run_os_command(['nmcli', 'connection', 'modify', profile, security_param, password])
              else
                # Fallback if security type can't be determined (e.g. out of range).
                run_os_command(['nmcli', 'dev', 'wifi', 'connect', network_name, 'password', password])
                return # The connect command already activates.
              end
            end
            # Always bring the connection up.
            run_os_command(['nmcli', 'connection', 'up', profile])
          else
            # No profile exists, create a new one.
            run_os_command(['nmcli', 'dev', 'wifi', 'connect', network_name, 'password', password])
          end
        else
          # Case 3: No password provided.
          profile = find_best_profile_for_ssid(network_name)
          if profile
            # Profile exists, try to bring it up with stored settings.
            run_os_command(['nmcli', 'connection', 'up', profile])
          else
            # No profile exists, try to connect to it as an open network.
            run_os_command(['nmcli', 'dev', 'wifi', 'connect', network_name])
          end
        end
      rescue WifiWand::CommandExecutor::OsCommandError => e
        # The nmcli command failed. Determine the specific failure reason.
        error_text = e.text || e.message || ''

        # Check for network not found errors
        if error_text.match?(/No network with SSID/i)
          raise WifiWand::NetworkNotFoundError, network_name
        end

        # Check for authentication/password errors
        # These patterns indicate wrong password or missing credentials
        if [
          /Secrets were required/i,
          /802-11-wireless-security.*No secrets/i,
          /authentication.*failed/i,
          /Connection activation failed.*\(7\)/i,
        ].any? { |pattern| error_text.match?(pattern) }
          raise WifiWand::NetworkAuthenticationError, network_name
        end

        # Check for device-related errors
        if [
          /No suitable device found/i,
          /Device.*not found/i,
        ].any? { |pattern| error_text.match?(pattern) }
          raise WifiWand::WifiInterfaceError, wifi_interface
        end

        # Generic connection activation failed - could indicate network out of range
        # or temporarily unavailable (not the same as "not found")
        if error_text.match?(/Connection activation failed/i)
          raise WifiWand::NetworkConnectionError.new(network_name,
            'Network may be out of range or temporarily unavailable')
        end

        # Re-raise the original error if it doesn't match known patterns
        raise e
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
      begin
        output = run_os_command(['nmcli', '-t', '-f', 'SSID,SECURITY', 'dev', 'wifi', 'list'], false).stdout
      rescue WifiWand::CommandExecutor::OsCommandError
        return nil # Can't scan, so can't determine the type.
      end

      network_line = output.split("\n").find { |line| nmcli_split(line, 2).first == ssid }
      return nil unless network_line

      # The output can be like "SSID:WPA2" or "SSID:WPA1 WPA2"
      security_type = nmcli_split(network_line, 2).last&.strip

      case canonical_security_type_from(security_type)
      when 'WPA3', 'WPA2', 'WPA'
        '802-11-wireless-security.psk'
      when 'WEP'
        '802-11-wireless-security.wep-key0'
      else
        # Unsupported, enterprise, or open network (shouldn't need password).
        nil
      end
    end

    # Preferred, clearer name for security parameter query
    def security_parameter(ssid) = get_security_parameter(ssid)

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

      begin
        output = run_os_command(['nmcli', '-t', '-f', 'NAME,TIMESTAMP', 'connection', 'show'], false).stdout
      rescue WifiWand::CommandExecutor::OsCommandError
        # If the command fails for any reason, we can't find profiles.
        return nil
      end

      profiles = output.split("\n").map do |line|
        name, timestamp = nmcli_split(line, 2)
        # Match exact profile name or NM duplicate suffixes: "MySSID", "MySSID 1", "MySSID 2", etc.
        if profile_matches_ssid?(name, ssid)
          { name: name, timestamp: timestamp.to_i }
        end
      end.compact

      # Find the profile with the highest (most recent) timestamp.
      profiles.max_by { |p| p[:timestamp] }&.dig(:name)
    end

    public

    def remove_preferred_network(network_name)
      debug_method_entry(__method__, binding, :network_name)

      matching_profiles = preferred_networks_matching_ssid(network_name)
      return [] if matching_profiles.empty?

      matching_profiles.each do |profile_name|
        run_os_command(['nmcli', 'connection', 'delete', profile_name])
      end
      matching_profiles
    end

    def has_preferred_network?(network_name)
      preferred_networks_matching_ssid(network_name.to_s).any?
    end

    def preferred_network_password(preferred_network_name)
      debug_method_entry(__method__, binding, :preferred_network_name)
      preferred_network_name = preferred_network_name.to_s
      if has_preferred_network?(preferred_network_name)
        resolved_profile_name = resolve_saved_profile_name(preferred_network_name)
        _preferred_network_password(resolved_profile_name)
      else
        raise PreferredNetworkNotFoundError, preferred_network_name
      end
    end

    def preferred_networks
      debug_method_entry(__method__)

      output = run_os_command(['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show']).stdout
      connections = output.split("\n")
        .map { |line| nmcli_split(line, 2) }
        .select { |_, type| type == '802-11-wireless' }
        .map { |name, _| name.strip }
        .reject(&:empty?)
      connections.sort
    end

    def _preferred_network_password(preferred_network_name)
      debug_method_entry(__method__, binding, :preferred_network_name)

      output = run_os_command(['nmcli', '--show-secrets', 'connection', 'show', preferred_network_name],
        false).stdout
      extract_preferred_network_secret(output)
    end

    def extract_preferred_network_secret(connection_output)
      secret_line = connection_output.split("\n").find do |line|
        PREFERRED_NETWORK_SECRET_FIELDS.any? { |field_name| line.include?("#{field_name}:") }
      end
      return nil unless secret_line

      secret = secret_line.split(':', 2).last&.strip
      secret.empty? ? nil : secret
    end

    def _ip_address
      debug_method_entry(__method__)

      output = run_os_command(['ip', '-4', 'addr', 'show', wifi_interface], false).stdout
      inet_line = output.split("\n").find { |line| line.include?('inet ') }
      return nil unless inet_line

      # Extract the inet address (e.g., "192.168.1.5/24" -> "192.168.1.5")
      inet_line.split.each do |token|
        return token.split('/').first if token.include?('/')
      end
      nil
    end

    def mac_address
      debug_method_entry(__method__)

      output = run_os_command(['ip', 'link', 'show', wifi_interface], false).stdout
      ether_line = output.split("\n").find { |line| line.include?('ether') }
      return nil unless ether_line

      # Extract MAC address (field after 'link/ether')
      tokens = ether_line.split
      ether_index = tokens.index('link/ether')
      ether_index ? tokens[ether_index + 1] : nil
    end

    def _disconnect
      debug_method_entry(__method__)

      interface = wifi_interface
      begin
        run_os_command(['nmcli', 'dev', 'disconnect', interface])
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

      # Prefer the active NetworkManager profile when querying DNS
      current_connection = active_connection_profile_name || _connected_network_name
      if current_connection
        connection_nameservers = nameservers_from_connection(current_connection)
        return connection_nameservers unless connection_nameservers.empty?
      end

      # Fallback to system resolver if no connection-specific DNS
      nameservers_using_resolv_conf || []
    end

    def set_nameservers(nameservers) # rubocop:disable Naming/AccessorMethodName
      # Use NetworkManager connection-based DNS configuration
      # This is the correct approach for Ubuntu - we modify the connection profile,
      # not the interface directly. Each Wi-Fi network has its own connection profile
      # which can have different DNS settings.

      debug_method_entry(__method__, binding, :nameservers)

      # Get the current active Wi-Fi connection name
      current_connection = active_connection_profile_name || _connected_network_name
      unless current_connection
        raise WifiInterfaceError, 'No active Wi-Fi connection to configure DNS for.'
      end

      if nameservers == :clear
        # Clear custom DNS and use DHCP/router-provided DNS (both IPv4 and IPv6)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv4.dns', ''], false)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv4.ignore-auto-dns', 'no'],
          false)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv6.dns', ''], false)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv6.ignore-auto-dns', 'no'],
          false)
      else
        # Validate IP addresses (accept both IPv4 and IPv6)
        bad_addresses = nameservers.reject do |ns|
          require 'ipaddr'
          IPAddr.new(ns)  # Valid if IPAddr can parse it (IPv4 or IPv6)
          true
        rescue
          false
        end

        unless bad_addresses.empty?
          raise InvalidIPAddressError, bad_addresses
        end

        # Separate IPv4 and IPv6 addresses
        ipv4_servers, ipv6_servers = nameservers.partition { |ns| IPAddr.new(ns).ipv4? }

        # Apply DNS as an exact replacement for both families so omitted
        # address families are cleared and return to DHCP/router-provided DNS.
        ipv4_dns_string = ipv4_servers.join(' ')
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv4.dns',
          ipv4_dns_string], false)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv4.ignore-auto-dns',
          ipv4_servers.any? ? 'yes' : 'no'], false)

        ipv6_dns_string = ipv6_servers.join(' ')
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv6.dns',
          ipv6_dns_string], false)
        run_os_command(['nmcli', 'connection', 'modify', current_connection, 'ipv6.ignore-auto-dns',
          ipv6_servers.any? ? 'yes' : 'no'], false)
      end

      # Restart the connection to apply DNS changes
      run_os_command(['nmcli', 'connection', 'up', current_connection], false)

      nameservers
    end

    def open_resource(resource_url)
      debug_method_entry(__method__, binding, :resource_url)

      run_os_command(['xdg-open', resource_url])
    end

    def active_connection_profile_name
      debug_method_entry(__method__)

      interface = wifi_interface
      return nil unless interface

      begin
        output = run_os_command(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', interface],
          false).stdout
      rescue WifiWand::CommandExecutor::OsCommandError
        return nil
      end

      line = output.split("\n").find { |row| row.start_with?('GENERAL.CONNECTION:') }
      return nil unless line

      profile = line.split(':', 2).last&.strip
      profile&.empty? ? nil : profile
    end

    # Returns the network interface used for default internet route on Linux
    def default_interface
      debug_method_entry(__method__)

      begin
        output = run_os_command(%w[ip route show default], false).stdout
        return nil if output.empty?

        # Extract interface name (5th field in: "default via 192.168.1.1 dev wlp0s20f3 ...")
        tokens = output.split("\n").first&.split
        dev_index = tokens&.index('dev')
        dev_index ? tokens[dev_index + 1] : nil
      rescue WifiWand::CommandExecutor::OsCommandError
        nil
      end
    end

    # Gets DNS nameservers configured for a specific connection profile
    # This is the NetworkManager connection-based approach for getting DNS
    def nameservers_from_connection(connection_name)
      debug_method_entry(__method__, binding, :connection_name)

      begin
        output = run_os_command(['nmcli', 'connection', 'show', connection_name], false).stdout

        # Extract DNS servers from connection configuration
        # Look for both configured DNS (ipv4.dns[1]:) and runtime DNS (IP4.DNS[1]:)
        # Format examples:
        #   ipv4.dns[1]:                        1.1.1.1    (static configuration)
        #   IP4.DNS[1]:                         192.168.3.1 (active/runtime state)
        # Note: ipv4.dns is documented in NetworkManager official docs, IP4.DNS observed in practice

        ip_version_pattern = /(?i)ip(?:v?[46])/    # Matches 'ipv4', 'ip4', 'ipv6', 'ip6'
        dns_field_pattern = /\.dns\[\d+\]:/       # Matches '.dns[N]:'

        # Use .source to get the raw pattern, ensuring flags apply uniformly to the new regex.
        dns_line_pattern = /#{ip_version_pattern.source}#{dns_field_pattern.source}/i

        dns_lines = output.split("\n").grep(dns_line_pattern)

        dns_lines.map do |line|
          # Split only on the first colon so IPv6 addresses (which contain colons) are preserved
          line.split(':', 2).last.strip
        end.reject(&:empty?)
      rescue WifiWand::CommandExecutor::OsCommandError
        # If we can't get connection info, return empty array
        []
      end
    end

    # Splits a line of nmcli terse (-t) output on unescaped field separators.
    # nmcli escapes literal colons in values as \:; this method splits only on
    # unescaped colons and then unescapes each resulting field.
    #
    # @param line [String] A line of nmcli -t terse output
    # @param limit [Integer, nil] Maximum number of parts to produce
    # @return [Array<String>] Unescaped field values
    def nmcli_split(line, limit = nil)
      parts = limit ? line.split(/(?<!\\):/, limit) : line.split(/(?<!\\):/)
      parts.map { |p| p.gsub('\\:', ':') }
    end

    def preferred_networks_matching_ssid(ssid)
      preferred_networks.select { |profile_name| profile_matches_ssid?(profile_name, ssid.to_s) }
    end

    def resolve_saved_profile_name(network_name)
      explicit_duplicate_profile =
        duplicate_profile_name?(network_name) && preferred_networks.include?(network_name)

      explicit_duplicate_profile ? network_name : find_best_profile_for_ssid(network_name) || network_name
    end

    def duplicate_profile_name?(network_name)
      network_name.match?(/\A.+ \d+\z/)
    end

    # Returns true when a connection profile name corresponds to a given SSID.
    # NetworkManager names the first profile exactly after the SSID; subsequent
    # duplicates get a space-separated integer suffix ("SSID 1", "SSID 2", …).
    #
    # @param profile_name [String] The connection profile name from nmcli
    # @param ssid [String] The target SSID
    # @return [Boolean]
    def profile_matches_ssid?(profile_name, ssid)
      profile_name == ssid || profile_name.match?(/\A#{Regexp.escape(ssid)} \d+\z/)
    end

    # Gets nameservers from /etc/resolv.conf - fallback method
    def nameservers_using_resolv_conf
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end

    # Gets the security type of the currently connected network.
    # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP", "None", or nil if not connected/not found
    def connection_security_type
      debug_method_entry(__method__)

      network_name = _connected_network_name
      return nil unless network_name

      begin
        output = run_os_command(['nmcli', '-t', '-f', 'SSID,SECURITY', 'dev', 'wifi', 'list'], false).stdout
      rescue WifiWand::CommandExecutor::OsCommandError
        return nil # Can't scan, return nil
      end

      network_line = output.split("\n").find { |line| nmcli_split(line, 2).first == network_name }
      return nil unless network_line

      # The output can be like "SSID:WPA2" or "SSID:WPA1 WPA2"
      security_type = nmcli_split(network_line, 2).last&.strip

      # Normalize via shared logic (returns nil for open/enterprise/unknown)
      canonical_security_type_from(security_type)
    end

    # Checks if the currently connected network is a hidden network.
    # A hidden network does not broadcast its SSID.
    # @return [Boolean] true if connected to a hidden network, false otherwise
    def network_hidden?
      debug_method_entry(__method__)

      network_name = _connected_network_name
      return false unless network_name

      # Get the active connection profile name
      profile_name = active_connection_profile_name || network_name

      begin
        # Query the connection profile to check if it's marked as hidden
        output = run_os_command(
          ['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name], false).stdout

        # The output will be like "802-11-wireless.hidden:yes" or "802-11-wireless.hidden:no"
        hidden_line = output.split("\n").find { |line| line.include?('802-11-wireless.hidden:') }
        return false unless hidden_line

        # Extract the value after the colon
        hidden_value = hidden_line.split(':', 2).last&.strip
        hidden_value == 'yes'
      rescue WifiWand::CommandExecutor::OsCommandError
        # If we can't get the connection info, assume it's not hidden
        false
      end
    end
  end
end
