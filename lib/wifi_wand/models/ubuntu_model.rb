# frozen_string_literal: true

require 'ipaddr'

require_relative 'base_model'
require_relative '../errors'
require_relative '../timing_constants'
require_relative '../services/status_line_data_builder'

module WifiWand
  class UbuntuModel < BaseModel
    PREFERRED_NETWORK_SECRET_FIELDS = %w[
      802-11-wireless-security.psk
      802-11-wireless-security.wep-key0
    ].freeze
    PREFERRED_NETWORK_SECRET_PLACEHOLDERS = %w[--].freeze
    ACTIVE_CONNECTION_PROFILE_PLACEHOLDERS = %w[--].freeze
    SAVED_WIFI_PROFILE_SUMMARY_FIELDS = 'NAME,TYPE,TIMESTAMP'
    SAVED_WIFI_PROFILE_SSID_FIELD = '802-11-wireless.ssid'
    DNS_CONNECTION_FIELDS = %w[
      ipv4.dns
      ipv4.ignore-auto-dns
      ipv6.dns
      ipv6.ignore-auto-dns
    ].freeze
    SavedWifiProfile = Struct.new(:name, :ssid, :type, :timestamp, keyword_init: true)

    def initialize(options = {}) = super

    def self.os_id
      :ubuntu
    end

    def status_line_data(progress_callback: nil)
      StatusLineDataBuilder.call(
        self,
        progress_callback:                          progress_callback,
        runtime_config:                             runtime_config,
        expected_network_errors:                    EXPECTED_NETWORK_ERRORS,
        connectivity_worker_result_timeout_seconds: TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
      )
    end

    def validate_os_preconditions
      missing_commands = []

      # Check for critical commands
      missing_commands << 'iw (install: sudo apt install iw)' unless command_available?('iw')
      unless command_available?('nmcli')
        missing_commands << 'nmcli (install: sudo apt install network-manager)'
      end
      missing_commands << 'ip (install: sudo apt install iproute2)' unless command_available?('ip')

      unless missing_commands.empty?
        raise CommandNotFoundError, missing_commands
      end

      :ok
    end

    def probe_wifi_interface(timeout_in_secs: nil)
      debug_method_entry(__method__)
      lines = run_command(
        %w[iw dev],
        timeout_in_secs: timeout_in_secs
      ).stdout.lines.map(&:strip)
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

    def is_wifi_interface?(interface, timeout_in_secs: nil)
      result = run_command(['iw', 'dev', interface, 'info'],
        raise_on_error: false, timeout_in_secs: timeout_in_secs)
      result.success?
    end

    def wifi_on?
      nmcli_wifi_radio_enabled?
    end

    def connected?
      return false unless wifi_on?

      output = run_command(
        ['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false
      ).stdout
      output.split("\n").any? { |line| line.strip == wifi_interface }
    end

    private def disconnect_associated?
      return false unless wifi_on?

      result = run_command(
        ['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'], raise_on_error: false
      )
      raise WifiWand::CommandExecutor::OsCommandError.new(result: result) unless result.success?

      result.stdout.split("\n").any? { |line| line.strip == wifi_interface }
    end

    def status_network_identity(timeout_in_secs: nil)
      deadline = status_deadline(timeout_in_secs)
      validate_os_preconditions unless @wifi_interface
      connected = status_connected?(deadline)
      network_name = connected ? status_connected_network_name(deadline) : nil

      {
        connected:    connected,
        network_name: network_name,
      }
    end

    def status_wifi_on?(timeout_in_secs: nil)
      deadline = status_deadline(timeout_in_secs)
      validate_os_preconditions unless @wifi_interface

      wifi_on_before_deadline?(deadline)
    end

    def connection_ready?(network_name)
      return false unless _connected_network_name == network_name
      return false if active_connection_profile_name.nil?
      return false unless connected?

      true
    rescue WifiWand::Error => e
      out_stream.puts("connection_ready? check failed: #{e.class}: #{e.message}") if verbose?
      false
    end

    def wifi_on
      return if wifi_on?

      run_command(%w[nmcli radio wifi on])
      till(:wifi_on, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      wifi_on? ? nil : raise(WifiEnableError)
    rescue WifiWand::WaitTimeoutError
      raise WifiEnableError
    end

    def wifi_off
      return unless wifi_on?

      run_command(%w[nmcli radio wifi off])
      till(:wifi_off, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      wifi_on? ? raise(WifiDisableError) : nil
    rescue WifiWand::WaitTimeoutError
      raise WifiDisableError
    end

    def _available_network_names
      debug_method_entry(__method__)

      output = run_command(['nmcli', '-t', '-f', 'SSID,SIGNAL', 'dev', 'wifi', 'list']).stdout
      networks_with_signal = output.split("\n").map(&:strip).reject(&:empty?)

      # Parse SSID and signal strength, then sort by signal (descending)
      networks = networks_with_signal.map do |line|
        ssid, signal = nmcli_split(line, 2)
        [ssid, signal.to_i]
      end
      networks = networks.sort_by { |_, signal| -signal }
      networks = networks.map { |ssid, _| ssid }.reject(&:empty?)

      networks.uniq
    end

    def _connected_network_name
      interface = wifi_interface
      return nil unless interface

      output = run_command(['iw', 'dev', interface, 'link'], raise_on_error: false).stdout
      return nil if output.strip.start_with?('Not connected')

      ssid_line = output.split("\n").find { |line| line.strip.start_with?('SSID:') }
      return nil unless ssid_line

      ssid = ssid_line.strip.delete_prefix('SSID:').strip
      ssid.empty? ? nil : ssid
    end

    private def status_connected?(deadline)
      return false unless wifi_on_before_deadline?(deadline)

      interface = status_wifi_interface(deadline)
      return false unless interface

      output = run_command(
        ['nmcli', '-t', '-f', 'DEVICE', 'connection', 'show', '--active'],
        raise_on_error:  false,
        timeout_in_secs: status_timeout_for(deadline)
      ).stdout
      output.split("\n").any? { |line| line.strip == interface }
    end

    private def wifi_on_before_deadline?(deadline)
      nmcli_wifi_radio_enabled?(timeout_in_secs: status_timeout_for(deadline))
    end

    private def nmcli_wifi_radio_enabled?(timeout_in_secs: nil)
      command_options = { raise_on_error: false }
      command_options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs
      result = run_command(%w[nmcli radio wifi], **command_options)
      raise WifiWand::CommandExecutor::OsCommandError.new(result: result) unless result.success?

      result.stdout.match?(/enabled/)
    end

    private def status_connected_network_name(deadline)
      interface = status_wifi_interface(deadline)
      return nil unless interface

      output = run_command(
        ['iw', 'dev', interface, 'link'],
        raise_on_error:  false,
        timeout_in_secs: status_timeout_for(deadline)
      ).stdout
      return nil if output.strip.start_with?('Not connected')

      ssid_line = output.split("\n").find { |line| line.strip.start_with?('SSID:') }
      return nil unless ssid_line

      ssid = ssid_line.strip.delete_prefix('SSID:').strip
      ssid.empty? ? nil : ssid
    end

    private def status_wifi_interface(deadline)
      return @wifi_interface if @wifi_interface

      @wifi_interface = probe_wifi_interface(timeout_in_secs: status_timeout_for(deadline))
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
        profile = find_best_profile_for_ssid(network_name)
        if password
          # Case 2: Password is provided.
          if profile
            activate_existing_profile_with_password(network_name, password, profile)
          else
            # No profile exists, create a new one.
            # Intentionally pass the caller-supplied password through to nmcli.
            # wifi-wand is designed for single-user machines under the operator
            # control, and showing the exact supplied credential is useful when
            # troubleshooting failed joins in verbose mode.
            run_command(['nmcli', 'dev', 'wifi', 'connect', network_name, 'password', password])
          end
        elsif profile
          # Case 3a: No password provided and a profile exists.
          # Try to bring it up with stored settings.
          run_command(['nmcli', 'connection', 'up', profile])
        else
          # Case 3b: No password provided and no profile exists.
          # Try to connect to it as an open network.
          run_command(['nmcli', 'dev', 'wifi', 'connect', network_name])
        end
      rescue WifiWand::CommandExecutor::OsCommandError => e
        # The nmcli command failed. Determine the specific failure reason.
        error_text = e.text || e.message || ''

        # Check for network not found errors
        if error_text.match?(/No network with SSID/i)
          raise(WifiWand::NetworkNotFoundError.new(network_name: network_name))
        end

        # Check for authentication/password errors
        # These patterns indicate wrong password or missing credentials
        if [
          /Secrets were required/i,
          /802-11-wireless-security.*No secrets/i,
          /authentication.*failed/i,
          /Connection activation failed.*\(7\)/i,
        ].any? { |pattern| error_text.match?(pattern) }
          raise(WifiWand::NetworkAuthenticationError.new(network_name: network_name))
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
          raise(WifiWand::NetworkConnectionError.new(
            network_name: network_name,
            reason:       'Network may be out of range or temporarily unavailable'
          ))
        end

        # Re-raise the original error if it doesn't match known patterns
        raise e
      end
    end

    public def connect(network_name, password = nil, skip_saved_password_lookup: false)
      with_saved_wifi_profiles_cache do
        super
      end
    end

    public def remove_preferred_networks(*network_names)
      network_names = network_names.first if network_names.first.is_a?(Array) && network_names.size == 1
      network_names = network_names.map(&:to_s).uniq

      with_saved_wifi_profiles_cache do
        super(*network_names)
      end
    end

    private def get_security_parameter(ssid)
      debug_method_entry(__method__, binding, :ssid)

      # Use the terse, machine-readable output to get the security protocol.
      begin
        output = run_command(
          ['nmcli', '-t', '-f', 'SSID,SECURITY', 'dev', 'wifi', 'list'], raise_on_error: false
        ).stdout
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
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
    private def security_parameter(ssid) = get_security_parameter(ssid)

    private def activate_existing_profile_with_password(network_name, password, profile)
      old_password = _preferred_network_password(profile)
      security_param = nil

      if password != old_password
        security_param = security_parameter_for_existing_profile(network_name, profile)
        if security_param
          run_command(['nmcli', 'connection', 'modify', profile, security_param, password])
        end
      end

      run_command(['nmcli', 'connection', 'up', profile])
    rescue WifiWand::CommandExecutor::OsCommandError => e
      if security_param && old_password
        rollback_existing_profile_password(profile, security_param, old_password)
      end
      raise e
    end

    private def security_parameter_for_existing_profile(network_name, profile)
      get_security_parameter(network_name) || preferred_network_secret_parameter(profile)
    end

    private def preferred_network_secret_parameter(profile)
      output = run_command(
        ['nmcli', '--show-secrets', 'connection', 'show', profile], raise_on_error: false
      ).stdout

      PREFERRED_NETWORK_SECRET_FIELDS.find do |field_name|
        output.split("\n").any? { |line| line.include?("#{field_name}:") }
      end
    end

    private def rollback_existing_profile_password(profile, security_param, old_password)
      run_command(['nmcli', 'connection', 'modify', profile, security_param, old_password])
    rescue WifiWand::CommandExecutor::OsCommandError => e
      out_stream.puts("Password rollback failed for #{profile}: #{e.message}") if verbose?
    end

    # Finds the best connection profile for a given SSID.
    # "Best" is defined as the one with the most recent TIMESTAMP, which indicates
    # it was the most recently used or configured. This helps solve the problem
    # of duplicate connection names (e.g., "MySSID", "MySSID 1").
    #
    # @param ssid [String] The SSID to search for.
    # @return [String, nil] The name of the best profile, or nil if none are found.
    private def find_best_profile_for_ssid(ssid)
      debug_method_entry(__method__, binding, :ssid)

      saved_wifi_profiles_matching_ssid(ssid).max_by(&:timestamp)&.name
    end

    public def remove_preferred_network(network_name)
      debug_method_entry(__method__, binding, :network_name)

      matching_profiles = preferred_networks_matching_ssid(network_name)
      if matching_profiles.empty?
        []
      else
        matching_profiles.each do |profile_name|
          run_command(['nmcli', 'connection', 'delete', profile_name])
        end
        matching_profiles
      end
    end

    public def has_preferred_network?(network_name)
      with_saved_wifi_profiles_cache do
        preferred_networks_matching_ssid(network_name.to_s).any?
      end
    end

    public def preferred_network_password(preferred_network_name, timeout_in_secs: :default)
      debug_method_entry(__method__, binding, :preferred_network_name)

      with_saved_wifi_profiles_cache do
        preferred_network_name = preferred_network_name.to_s
        if (resolved_profile_name = find_best_profile_for_ssid(preferred_network_name))
          _preferred_network_password(resolved_profile_name, timeout_in_secs: timeout_in_secs)
        else
          raise PreferredNetworkNotFoundError, preferred_network_name
        end
      end
    end

    public def preferred_networks
      debug_method_entry(__method__)

      with_saved_wifi_profiles_cache do
        saved_wifi_profiles.map(&:ssid).reject(&:empty?).uniq.sort
      end
    end

    public def _preferred_network_password(preferred_network_name, timeout_in_secs: :default)
      debug_method_entry(__method__, binding, :preferred_network_name)

      command_options = { raise_on_error: false }
      command_options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs && timeout_in_secs != :default
      output = run_command(
        ['nmcli', '--show-secrets', 'connection', 'show', preferred_network_name], **command_options
      ).stdout
      extract_preferred_network_secret(output)
    end

    public def extract_preferred_network_secret(connection_output)
      connection_lines = connection_output.split("\n")

      PREFERRED_NETWORK_SECRET_FIELDS.each do |field_name|
        secret_line = connection_lines.find { |line| line.include?("#{field_name}:") }
        next unless secret_line

        secret = secret_line.split(':', 2).last&.strip
        next unless preferred_network_secret_value?(secret)

        return secret
      end

      nil
    end

    private def preferred_network_secret_value?(secret)
      return false if string_nil_or_empty?(secret)

      !PREFERRED_NETWORK_SECRET_PLACEHOLDERS.include?(secret)
    end

    public def _ip_address
      debug_method_entry(__method__)

      output = run_command(['ip', '-4', 'addr', 'show', wifi_interface],
        raise_on_error: false).stdout
      inet_line = output.split("\n").find { |line| line.include?('inet ') }
      return nil unless inet_line

      # Extract the inet address (e.g., "192.168.1.5/24" -> "192.168.1.5")
      inet_line.split.each do |token|
        return token.split('/').first if token.include?('/')
      end
      nil
    end

    public def mac_address
      debug_method_entry(__method__)

      output = run_command(['ip', 'link', 'show', wifi_interface], raise_on_error: false).stdout
      ether_line = output.split("\n").find { |line| line.include?('ether') }
      return nil unless ether_line

      # Extract MAC address (field after 'link/ether')
      tokens = ether_line.split
      ether_index = tokens.index('link/ether')
      ether_index ? tokens[ether_index + 1] : nil
    end

    public def _disconnect
      debug_method_entry(__method__)

      interface = wifi_interface
      begin
        run_command(['nmcli', 'dev', 'disconnect', interface])
      rescue WifiWand::CommandExecutor::OsCommandError => e
        # It's normal for disconnect to fail if there's no active connection
        # Common scenarios: device not active, not connected to any network
        return nil if e.exitstatus == 6

        raise e
      end
      nil
    end

    public def nameservers
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

    # Applies DNS as an exact replacement and rolls the profile back to its
    # original DNS state if any later modify or reactivation step fails.
    public def set_nameservers(nameservers) # rubocop:disable Naming/AccessorMethodName
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

      desired_dns_configuration = desired_dns_configuration(nameservers)
      original_dns_configuration = dns_configuration_snapshot(current_connection)
      configuration_changed = false

      dns_configuration_modify_commands(current_connection, desired_dns_configuration).each do |command|
        run_command(command)
        configuration_changed = true
      end
      run_command(['nmcli', 'connection', 'up', current_connection])

      nameservers
    rescue WifiWand::CommandExecutor::OsCommandError => e
      step = e.command.include?('connection up') ? :activate : :modify
      if configuration_changed
        begin
          restore_dns_configuration(current_connection, original_dns_configuration)
        rescue WifiWand::CommandExecutor::OsCommandError => rollback_error
          raise(DnsConfigurationError.new(
            connection_name: current_connection,
            step:            step,
            cause_error:     dns_transaction_failure(e, rollback_error)
          ))
        end
      end

      raise(DnsConfigurationError.new(connection_name: current_connection, step: step, cause_error: e))
    end

    public def open_resource(resource_url)
      debug_method_entry(__method__, binding, :resource_url)

      run_command(['xdg-open', resource_url])
    end

    public def active_connection_profile_name
      debug_method_entry(__method__)

      interface = wifi_interface
      return nil unless interface

      begin
        output = run_command(['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'dev', 'show', interface],
          raise_on_error: false).stdout
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
        return nil
      end

      line = output.split("\n").find { |row| nmcli_split(row, 2).first == 'GENERAL.CONNECTION' }
      return nil unless line

      profile = nmcli_split(line, 2).last
      normalize_active_connection_profile_name(profile)
    end

    # Returns the network interface used for default internet route on Linux
    public def default_interface
      debug_method_entry(__method__)

      begin
        output = run_command(%w[ip route show default], raise_on_error: false).stdout
        return nil if output.empty?

        # Extract interface name (5th field in: "default via 192.168.1.1 dev wlp0s20f3 ...")
        tokens = output.split("\n").first&.split
        dev_index = tokens&.index('dev')
        dev_index ? tokens[dev_index + 1] : nil
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
        nil
      end
    end

    # Gets DNS nameservers configured for a specific connection profile
    # This is the NetworkManager connection-based approach for getting DNS
    public def nameservers_from_connection(connection_name)
      debug_method_entry(__method__, binding, :connection_name)

      begin
        output = run_command(['nmcli', 'connection', 'show', connection_name],
          raise_on_error: false).stdout

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
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
        # If we can't get connection info, return empty array
        []
      end
    end

    public def desired_dns_configuration(nameservers)
      if nameservers == :clear
        return {
          'ipv4.dns'             => '',
          'ipv4.ignore-auto-dns' => 'no',
          'ipv6.dns'             => '',
          'ipv6.ignore-auto-dns' => 'no',
        }
      end

      # Validate IP addresses (accept both IPv4 and IPv6)
      bad_addresses = nameservers.reject do |ns|
        IPAddr.new(ns) # Valid if IPAddr can parse it (IPv4 or IPv6)
        true
      rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
        false
      end

      unless bad_addresses.empty?
        raise InvalidIPAddressError, bad_addresses
      end

      ipv4_servers, ipv6_servers = nameservers.partition { |ns| IPAddr.new(ns).ipv4? }

      {
        'ipv4.dns'             => ipv4_servers.join(' '),
        'ipv4.ignore-auto-dns' => ipv4_servers.any? ? 'yes' : 'no',
        'ipv6.dns'             => ipv6_servers.join(' '),
        'ipv6.ignore-auto-dns' => ipv6_servers.any? ? 'yes' : 'no',
      }
    end

    # Reads the current profile values up front so rollback can restore the
    # exact pre-transaction state instead of inferring defaults.
    public def dns_configuration_snapshot(connection_name)
      DNS_CONNECTION_FIELDS.to_h do |field_name|
        [field_name, connection_property_value(connection_name, field_name)]
      end
    end

    public def dns_configuration_modify_commands(connection_name, dns_configuration)
      DNS_CONNECTION_FIELDS.map do |field_name|
        ['nmcli', 'connection', 'modify', connection_name, field_name,
          dns_configuration.fetch(field_name)]
      end
    end

    # Replays the captured DNS fields and reactivates the profile so callers
    # are not left with a partially applied DNS configuration.
    public def restore_dns_configuration(connection_name, original_dns_configuration)
      dns_configuration_modify_commands(connection_name, original_dns_configuration).each do |command|
        run_command(command)
      end
      run_command(['nmcli', 'connection', 'up', connection_name])
    end

    public def connection_property_value(connection_name, field_name)
      run_command(['nmcli', '--get-values', field_name, 'connection', 'show',
        connection_name]).stdout.strip
    end

    # Preserves the original failure while surfacing that rollback also failed,
    # which means the connection profile may still need manual repair.
    public def dns_transaction_failure(original_error, rollback_error)
      original_detail = if original_error.respond_to?(:text) && !original_error.text.to_s.empty?
        original_error.text
      else
        original_error.message
      end
      rollback_detail = if rollback_error.respond_to?(:text) && !rollback_error.text.to_s.empty?
        rollback_error.text
      else
        rollback_error.message
      end

      Error.new("#{original_detail}; rollback failed: #{rollback_detail}")
    end

    # Splits a line of nmcli terse (-t) output on unescaped field separators.
    # nmcli escapes literal colons as \: and literal backslashes as \\.
    #
    # @param line [String] A line of nmcli -t terse output
    # @param limit [Integer, nil] Maximum number of parts to produce
    # @return [Array<String>] Unescaped field values
    public def nmcli_split(line, limit = nil)
      parts = []
      field = +''
      escaped = false

      line.each_char do |char|
        if escaped
          unescaped_char = if [':', '\\'].include?(char)
            char
          else
            "\\#{char}"
          end
          field << unescaped_char
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == ':' && (limit.nil? || parts.length < limit - 1)
          parts << field
          field = +''
        else
          field << char
        end
      end

      field << '\\' if escaped
      parts << field
    end

    private def normalize_active_connection_profile_name(profile)
      normalized_profile = profile&.strip
      if normalized_profile.nil? ||
          normalized_profile.empty? ||
          ACTIVE_CONNECTION_PROFILE_PLACEHOLDERS.include?(normalized_profile)
        nil
      else
        normalized_profile
      end
    end

    private def saved_wifi_profiles
      return saved_wifi_profiles_from_summary_query unless @saved_wifi_profiles_cache_active

      unless @saved_wifi_profiles_cache_loaded
        @saved_wifi_profiles_cache = saved_wifi_profiles_from_summary_query
        @saved_wifi_profiles_cache_loaded = true
      end
      @saved_wifi_profiles_cache
    end

    private def saved_wifi_profiles_from_summary_query
      # raise_on_error is false so nmcli exit failures can be handled explicitly.
      result = run_command(
        ['nmcli', '-t', '-f', SAVED_WIFI_PROFILE_SUMMARY_FIELDS, 'connection', 'show'], raise_on_error: false
      )
      return [] unless result.success?

      result.stdout.split("\n").filter_map do |line|
        name, type, timestamp = nmcli_split(line, 3)
        ssid = saved_wifi_profile_ssid(name) if type == '802-11-wireless'
        saved_wifi_profile_from_fields(name: name, ssid: ssid, type: type, timestamp: timestamp)
      end
    rescue WifiWand::CommandTimeoutError, WifiWand::CommandNotFoundError, WifiWand::CommandSpawnError
      []
    end

    private def saved_wifi_profile_from_fields(name:, ssid:, type:, timestamp:)
      return unless type == '802-11-wireless'
      return if string_nil_or_empty?(ssid)

      SavedWifiProfile.new(name: name, ssid: ssid, type: type, timestamp: timestamp.to_i)
    end

    private def saved_wifi_profile_ssid(profile_name)
      output = run_command(
        ['nmcli', '-t', '-f', SAVED_WIFI_PROFILE_SSID_FIELD, 'connection', 'show', profile_name],
        raise_on_error: false
      ).stdout
      line = output.split("\n").find { |output_line| !output_line.empty? }
      return nil unless line

      field_name, ssid = nmcli_split(line, 2)
      field_name == SAVED_WIFI_PROFILE_SSID_FIELD ? ssid : nil
    rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
      nil
    end

    private def with_saved_wifi_profiles_cache
      if @saved_wifi_profiles_cache_active
        yield
      else
        @saved_wifi_profiles_cache_active = true
        @saved_wifi_profiles_cache = nil
        @saved_wifi_profiles_cache_loaded = false
        begin
          yield
        ensure
          @saved_wifi_profiles_cache = nil
          @saved_wifi_profiles_cache_loaded = false
          @saved_wifi_profiles_cache_active = false
        end
      end
    end

    private def saved_wifi_profiles_matching_ssid(ssid)
      ssid = ssid.to_s
      saved_wifi_profiles.select { |profile| profile.ssid == ssid }
    end

    public def preferred_networks_matching_ssid(ssid)
      saved_wifi_profiles_matching_ssid(ssid).map(&:name)
    end

    public def resolve_saved_profile_name(network_name)
      find_best_profile_for_ssid(network_name) || network_name
    end

    # Gets the security type of the currently connected network.
    # @return [String, nil] The security type: "WPA", "WPA2", "WPA3", "WEP",
    #   "NONE" for open networks, or nil if not connected/not found
    public def connection_security_type
      debug_method_entry(__method__)

      network_name = _connected_network_name
      return nil unless network_name

      begin
        output = run_command(
          ['nmcli', '-t', '-f', 'IN-USE,SSID,SECURITY', 'dev', 'wifi', 'list'], raise_on_error: false
        ).stdout
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
        return nil # Can't scan, return nil
      end

      # Match NetworkManager's active BSS row, not just SSID, because duplicate SSIDs can
      # advertise different security modes.
      network_line = output.split("\n").find do |line|
        in_use, ssid, = nmcli_split(line, 3)
        in_use == '*' && ssid == network_name
      end
      return nil unless network_line

      # The output can be like "*:SSID:WPA2" or "*:SSID:WPA1 WPA2"
      security_type = nmcli_split(network_line, 3).last&.strip

      # nmcli reports open networks with an empty SECURITY field or a "--" placeholder.
      if security_type.to_s.empty? || security_type == '--'
        'NONE'
      else
        canonical_security_type_from(security_type)
      end
    end

    # Checks if the currently connected network is a hidden network.
    # A hidden network does not broadcast its SSID.
    # @return [Boolean] true if connected to a hidden network, false otherwise
    public def network_hidden?
      debug_method_entry(__method__)

      network_name = _connected_network_name
      return false unless network_name

      # Get the active connection profile name
      profile_name = active_connection_profile_name || network_name

      begin
        # Query the connection profile to check if it's marked as hidden
        output = run_command(
          ['nmcli', '-t', '-f', '802-11-wireless.hidden', 'connection', 'show', profile_name],
          raise_on_error: false
        ).stdout

        # The output will be like "802-11-wireless.hidden:yes" or "802-11-wireless.hidden:no"
        hidden_line = output.split("\n").find { |line| line.include?('802-11-wireless.hidden:') }
        return false unless hidden_line

        # Extract the value after the colon
        hidden_value = hidden_line.split(':', 2).last&.strip
        hidden_value == 'yes'
      rescue *WifiWand::BaseModel::NETWORK_OPERATION_COMMAND_ERRORS
        # If we can't get the connection info, assume it's not hidden
        false
      end
    end
  end
end
