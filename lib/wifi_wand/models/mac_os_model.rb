# frozen_string_literal: true

require 'ipaddr'
require 'shellwords'

require_relative 'base_model'
require_relative '../errors'
require_relative '../mac_helper/mac_os_swift_runtime'
require_relative '../mac_helper/mac_os_wifi_transport'
require_relative '../mac_helper/mac_os_helper_bundle'


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
    AIRPORT_COMMAND =
      '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'
    SYSTEM_PROFILER_AIRPORT_ARGS = %w[system_profiler -json SPAirPortDataType].freeze
    SYSTEM_PROFILER_NETWORK_ARGS = %w[system_profiler -json SPNetworkDataType].freeze
    AIRPORT_DATA_CACHE_CONTEXTS_KEY = :wifi_wand_airport_data_cache_contexts
    NO_CONNECTED_NETWORK = Object.new.freeze

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

    def fetch_hardware_ports(timeout_in_secs: nil)
      output = run_command_using_args(
        %w[networksetup -listallhardwareports],
        timeout_in_secs: timeout_in_secs
      ).stdout

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

    def wifi_port_from_ports(ports)
      ports.find do |port|
        name = port[:name].to_s
        next false if name.empty?

        WIFI_PORT_PATTERNS.any? { |pattern| pattern.match?(name) }
      end
    end

    def wifi_service_name_from_ports(ports)
      wifi_port = wifi_port_from_ports(ports)
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
    def macos_version(timeout_in_secs: nil)
      @macos_version ||= detect_macos_version(timeout_in_secs: timeout_in_secs)
    end

    def initialize(options = {})
      super
      # Defer macOS version detection until first needed to minimize incidental OS calls
      @macos_version = nil
      @mac_helper_client = nil
      @swift_runtime = nil
      @airport_data_cache_mutex = Mutex.new
      @airport_data_cache_generation = 0
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

    # Returns the Wi-Fi service name dynamically (e.g., "Wi-Fi", "AirPort", etc.)
    def wifi_service_name
      @wifi_service_name ||= wifi_service_name_from_ports(fetch_hardware_ports)
    end

    # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
    # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
    def detect_wifi_interface_using_networksetup(timeout_in_secs: nil)
      iface = wifi_interface_using_networksetup(timeout_in_secs: timeout_in_secs)
      raise WifiInterfaceError if iface.nil? || iface.empty?

      iface
    end

    # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
    # Prefer the faster networksetup path and fall back to system_profiler if needed.
    # This may not detect WiFi ports with nonstandard names, such as USB WiFi devices.
    def probe_wifi_interface(timeout_in_secs: nil)
      deadline = status_deadline(timeout_in_secs)
      begin
        iface = wifi_interface_using_networksetup(timeout_in_secs: status_timeout_for(deadline))
        return iface if iface && !iface.empty?
      rescue WifiWand::Error
        # Fall through to system_profiler fallback.
      end

      wifi_interface_using_system_profiler(timeout_in_secs: status_timeout_for(deadline))
    end

    # Returns the network names sorted in descending order of signal strength.
    def _available_network_names
      _available_network_scan.fetch('networks')
    end

    def available_network_scan
      raise WifiOffError, 'WiFi is off, cannot scan for available networks.' unless wifi_on?

      _available_network_scan
    end

    def _available_network_scan
      with_airport_data_cache_scope do
        helper_result = mac_helper_client.scan_networks
        helper_networks = helper_available_network_names_from_result(helper_result)
        return available_network_scan_result(helper_networks, source: 'mac_helper') if helper_networks

        fallback_networks = fallback_available_network_names
        if helper_result.location_services_blocked?
          return location_services_blocked_available_network_scan(fallback_networks)
        end

        available_network_scan_result(fallback_networks, source: 'fallback')
      end
    end

    # Queries available WiFi network names via the compiled macOS helper application.
    # macOS currently uses two Swift runtime paths:
    # - compiled helper application bundle for read/query operations that may
    #   need a stable app identity and Location Services handling
    # - direct Swift source execution for connect/disconnect mutations
    # Consolidating those paths is a future architecture task.
    #
    # Returns:
    #   - Array<String> of unique SSID names when the helper application returns usable data
    #   - nil when the helper application is unavailable, Location Services
    #     blocks the helper application, returns no networks, or all SSIDs are filtered placeholders
    #     (signals the caller to try fallback sources)
    #
    # Placeholder SSIDs such as "<hidden>" and "<redacted>" are excluded from
    # the result. All interpretation of the helper application response uses the
    # explicit HelperQueryResult returned by scan_networks—no hidden client state is
    # consulted.
    def helper_available_network_names
      result = mac_helper_client.scan_networks

      helper_available_network_names_from_result(result)
    end

    private def helper_available_network_names_from_result(result)
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

        # Query the compiled helper application path first because association
        # checks may still need the helper application's stable app identity to
        # return an unredacted SSID on modern macOS.
        result = mac_helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)
        return false if result.not_connected?

        interface_associated_in_airport_data?(wifi_interface_airport_data)
      end
    rescue WifiWand::Error
      false
    end

    def connected?
      with_airport_data_cache_scope do
        return false unless wifi_on?

        # On Sonoma+, system_profiler may omit spairport_current_network_information
        # entirely when SSID data is redacted. Check the compiled helper
        # application path first; it is the runtime used for read/query
        # operations that need CoreWLAN plus a stable app identity.
        result = mac_helper_client.connected_network_name
        return true if result.payload && !placeholder_network_name?(result.payload)
        return false if result.not_connected?

        interface_data = wifi_interface_airport_data
        return true if interface_associated_in_airport_data?(interface_data)

        associated_without_ssid?(interface_data)
      end
    end

    def status_network_identity(timeout_in_secs: nil)
      deadline = status_deadline(timeout_in_secs)

      with_airport_data_cache_scope do
        return { connected: false, network_name: nil } unless wifi_on_before_deadline?(deadline)

        helper_result = mac_helper_client.connected_network_name(
          timeout_seconds: status_timeout_for(deadline)
        )
        helper_ssid = helper_result.payload
        if helper_ssid && !placeholder_network_name?(helper_ssid)
          return { connected: true, network_name: helper_ssid }
        end
        return { connected: false, network_name: nil } if helper_result.not_connected?

        fast_network_name = status_network_name_using_fast_commands(deadline)
        return { connected: false, network_name: nil } if no_connected_network?(fast_network_name)
        return { connected: true, network_name: fast_network_name } if fast_network_name

        interface_data = wifi_interface_airport_data(deadline: deadline)
        connected = interface_associated_in_airport_data?(interface_data) ||
          status_associated_without_ssid?(deadline)
        network_name = connected ? status_network_name_from_airport_data(interface_data) : nil

        {
          connected:    connected,
          network_name: network_name,
        }
      end
    end

    def status_wifi_on?(timeout_in_secs: nil)
      deadline = status_deadline(timeout_in_secs)

      wifi_on_before_deadline?(deadline)
    end

    # Turns WiFi on.
    def wifi_on
      return if wifi_on?

      invalidate_airport_data_cache

      begin
        iface = wifi_interface
        run_command_using_args(['networksetup', '-setairportpower', iface, 'on'])
      ensure
        invalidate_airport_data_cache
      end

      wifi_on? ? nil : raise(WifiEnableError)
    end

    # Turns WiFi off.
    def wifi_off
      return unless wifi_on?

      invalidate_airport_data_cache

      begin
        iface = wifi_interface
        run_command_using_args(['networksetup', '-setairportpower', iface, 'off'])
      ensure
        invalidate_airport_data_cache
      end

      wifi_on? ? raise(WifiDisableError) : nil
    end

    # Connect mutations flow through the direct Swift-source transport path.
    # That path owns the Swift/CoreWLAN attempt plus fallback to traditional
    # macOS utilities when Swift is unavailable or the connect attempt fails in
    # known ways.
    def _connect(network_name, password = nil)
      invalidate_airport_data_cache
      mac_os_wifi_transport.connect(network_name, password)
    ensure
      invalidate_airport_data_cache
    end

    # Password lookups on macOS may block on a user-facing keychain approval
    # dialog, so the public lookup API defaults to waiting indefinitely unless
    # a caller explicitly requests a timeout.
    def preferred_network_password(preferred_network_name, timeout_in_secs: nil)
      super
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
        raise_on_error:  true,
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
        raise_on_error:  true,
        timeout_in_secs: SUDO_NETWORKSETUP_TIMEOUT_SECONDS
      )
      [network_name]
    end

    # Returns the network currently connected to, or nil if none.

    def connected_network_name
      raise WifiOffError, 'WiFi is off, cannot determine connected network.' unless wifi_on?

      @connected_network_authoritatively_disconnected = false
      @connected_network_fallback_identity_redacted = false

      with_airport_data_cache_scope do
        network_name = _connected_network_name
        return network_name if network_name
        return nil if connected_network_authoritatively_disconnected?

        if connected? && network_identity_redacted?
          raise MacOsRedactionError.new(
            operation_description: 'Current WiFi network queries',
            reason:                network_identity_redaction_reason
          )
        end

        nil
      end
    ensure
      @connected_network_authoritatively_disconnected = false
      @connected_network_fallback_identity_redacted = false
    end

    def _connected_network_name
      network_name = connected_network_name_candidate
      return mark_connected_network_authoritatively_disconnected if no_connected_network?(network_name)

      network_name
    end

    private def connected_network_name_candidate
      with_airport_data_cache_scope do
        # Current-network reads check the compiled helper application path first
        # because it is the read/query runtime with stable app identity and
        # Location Services handling.
        result = mac_helper_client.connected_network_name
        ssid = result.payload
        return ssid if ssid && !placeholder_network_name?(ssid)
        return nil if result.not_connected?

        fast_network_name = network_name_using_fast_commands
        return fast_network_name if no_connected_network?(fast_network_name)
        return fast_network_name if fast_network_name

        wifi_interface_data = wifi_interface_airport_data

        # Handle interface not found
        return nil unless wifi_interface_data

        # Handle no current network connection
        current_network = wifi_interface_data['spairport_current_network_information']
        return nil unless current_network

        # Return the network name (could still be nil)
        network_name = current_network.is_a?(Hash) ? current_network['_name'] : current_network
        return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

        network_name
      end
    end

    private def mark_connected_network_authoritatively_disconnected
      @connected_network_authoritatively_disconnected = true
      nil
    end

    private def connected_network_authoritatively_disconnected?
      @connected_network_authoritatively_disconnected
    end

    def network_identity_redacted?
      return true if connected_network_fallback_identity_redacted?

      with_airport_data_cache_scope do
        # Redaction detection is tied to the compiled helper application path
        # because that runtime surfaces Location Services blocking directly.
        result = mac_helper_client.connected_network_name
        result.location_services_error? ||
          helper_placeholder_network_name?(result.payload) ||
          fallback_network_identity_missing?
      end
    rescue WifiWand::Error
      false
    end

    def network_identity_redaction_reason
      return nil unless network_identity_redacted?

      'macOS is redacting WiFi network names until Location Services access is granted ' \
        'to wifiwand-helper, the macOS helper application'
    end

    private def mark_connected_network_fallback_identity_redacted
      @connected_network_fallback_identity_redacted = true
      nil
    end

    private def connected_network_fallback_identity_redacted?
      @connected_network_fallback_identity_redacted
    end

    private def fallback_network_identity_missing?
      wifi_interface_data = wifi_interface_airport_data
      current_network = wifi_interface_data&.fetch('spairport_current_network_information', nil)
      return false if current_network

      associated_without_ssid?(wifi_interface_data)
    end

    private def helper_placeholder_network_name?(network_name)
      !network_name.nil? && placeholder_network_name?(network_name)
    end

    def mac_helper_client
      @mac_helper_client ||= WifiWand::MacOsHelperClient.new(
        out_stream_proc:    -> { out_stream },
        err_stream_proc:    -> { err_stream },
        verbose_proc:       -> { verbose? },
        macos_version_proc: ->(timeout_in_secs: nil) { macos_version(timeout_in_secs: timeout_in_secs) }
      )
    end

    # Disconnects from the currently connected network. Does not turn off WiFi.
    # Disconnect mutations use the direct Swift-source transport path first,
    # with `ifconfig` fallback when the Swift/CoreWLAN path is unavailable or
    # fails.
    def _disconnect
      invalidate_airport_data_cache
      mac_os_wifi_transport.disconnect
    ensure
      invalidate_airport_data_cache
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
      service_name = wifi_service_name

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
      service_name = wifi_service_name
      output = run_command_using_args(['networksetup', '-getdnsservers', service_name]).stdout
      if output == "There aren't any DNS Servers set on #{service_name}.\n"
        output = ''
      end
      output.split("\n")
    end

    def nameservers = nameservers_using_scutil

    # Returns the network interface used for default internet route on macOS
    def default_interface
      output = run_command_using_args(%w[route -n get default], raise_on_error: false).stdout
      return nil if output.empty?

      # Find line containing 'interface:' and extract value
      interface_line = output.split("\n").find { |line| line.include?('interface:') }
      return nil unless interface_line

      interface_line.split.last
    rescue WifiWand::CommandExecutor::OsCommandError
      nil
    end

    # Detects the current macOS version
    def detect_macos_version(timeout_in_secs: nil)
      options = {}
      options[:timeout_in_secs] = timeout_in_secs if timeout_in_secs
      output = run_command_using_args(%w[sw_vers -productVersion], **options).stdout
      MacOsHelperBundle.normalize_detected_macos_version(output)
    rescue WifiWand::CommandExecutor::OsCommandError, WifiWand::CommandTimeoutError,
      WifiWand::CommandNotFoundError, WifiWand::CommandSpawnError => e
      if verbose?
        out_stream.puts "Could not detect macOS version: #{e.message}."
      end
      nil
    end

    def validate_os_preconditions(timeout_in_secs: nil)
      # All core read/status commands are built into macOS. The Swift/CoreWLAN
      # source runtime is mutation-specific and is probed lazily by the
      # connect/disconnect transport.
      :ok
    end

    private :wifi_service_name_from_ports,
      :fetch_hardware_ports,
      :wifi_port_from_ports,
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

    private def network_name_using_fast_commands(timeout_in_secs: nil)
      network_name = connected_network_name_using_networksetup(timeout_in_secs: timeout_in_secs)
      return network_name if network_name

      connected_network_name_using_airport(timeout_in_secs: timeout_in_secs)
    end

    private def status_network_name_using_fast_commands(deadline)
      iface = status_wifi_interface(deadline)
      return nil unless iface

      network_name = connected_network_name_using_networksetup(
        iface:           iface,
        timeout_in_secs: status_timeout_for(deadline)
      )
      return network_name if network_name

      connected_network_name_using_airport(timeout_in_secs: status_timeout_for(deadline))
    end

    private def connected_network_name_using_networksetup(iface: wifi_interface, timeout_in_secs: nil)
      output = run_command_using_args(
        ['networksetup', '-getairportnetwork', iface],
        timeout_in_secs: timeout_in_secs
      ).stdout.strip
      return nil if output.empty?
      return NO_CONNECTED_NETWORK if output.match?(/not associated|power is currently off/i)

      match = output.match(/\ACurrent (?:Wi-Fi|AirPort) Network:\s*(.*)\z/)
      return nil unless match

      network_name = match[1].strip
      return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

      network_name
    rescue WifiWand::Error
      nil
    end

    private def connected_network_name_using_airport(timeout_in_secs: nil)
      output = run_command_using_args(
        [AIRPORT_COMMAND, '-I'],
        timeout_in_secs: timeout_in_secs
      ).stdout
      return nil if output.strip.empty?

      airport_info = colon_output_to_hash(output)
      network_name = airport_info['SSID']
      if airport_info.key?('SSID')
        return mark_connected_network_fallback_identity_redacted if placeholder_network_name?(network_name)

        return network_name
      end

      mark_connected_network_fallback_identity_redacted if airport_info['BSSID']
      nil
    rescue WifiWand::Error
      nil
    end

    private def airport_available_network_names(timeout_in_secs: nil)
      output = run_command_using_args(
        [AIRPORT_COMMAND, '-s'],
        timeout_in_secs: timeout_in_secs
      ).stdout
      networks = parse_airport_scan_output(output)
      networks.empty? ? nil : networks
    rescue WifiWand::Error
      nil
    end

    private def fallback_available_network_names
      airport_networks = airport_available_network_names
      return airport_networks if airport_networks

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

    private def available_network_scan_result(networks, source:, status: 'ok', trusted: true, warning: nil)
      {
        'networks'          => Array(networks),
        'scan_status'       => status,
        'scan_source'       => source,
        'ssid_data_trusted' => trusted,
        'warning'           => warning,
      }
    end

    private def location_services_blocked_available_network_scan(networks)
      available_network_scan_result(
        networks,
        source:  'fallback',
        status:  'location_services_blocked',
        trusted: false,
        warning: location_services_blocked_scan_warning
      )
    end

    private def location_services_blocked_scan_warning
      'macOS blocked wifiwand-helper from reading WiFi SSIDs through Location Services; ' \
        'fallback scan results may be incomplete or unavailable. Run `wifi-wand-macos-setup`, ' \
        'grant Location Services to `wifiwand-helper`, and retry.'
    end

    private def parse_airport_scan_output(output)
      scanned_networks = output.split("\n").drop(1).filter_map do |line|
        match = line.match(/\A\s*(.*?)\s+(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\s+(-?\d+)\s+/i)
        next unless match

        name = match[1].strip
        next if placeholder_network_name?(name)

        [name, match[2].to_i]
      end

      scanned_networks.sort_by { |_name, signal| -signal }.map(&:first).uniq
    end

    private def colon_output_to_hash(output)
      output.each_line.with_object({}) do |line, hash|
        key, value = line.split(':', 2)
        next unless key && !value.nil?

        hash[key.strip] = value.to_s.strip
      end
    end

    private def no_connected_network?(network_name)
      network_name.equal?(NO_CONNECTED_NETWORK)
    end

    private def wifi_interface_using_networksetup(timeout_in_secs: nil)
      ports = fetch_hardware_ports(timeout_in_secs: timeout_in_secs)
      service_name = wifi_service_name_from_ports(ports)
      @wifi_service_name = service_name if service_name && !service_name.empty?

      wifi_port = ports.find do |port|
        port[:name] == service_name && port[:device] && !port[:device].empty?
      end
      wifi_port ||= wifi_port_from_ports(ports)

      iface = wifi_port && wifi_port[:device]
      iface if iface && !iface.empty?
    end

    private def wifi_interface_using_system_profiler(timeout_in_secs: nil)
      json_text = run_command_using_args(
        SYSTEM_PROFILER_NETWORK_ARGS,
        raise_on_error:  true,
        timeout_in_secs: timeout_in_secs || SYSTEM_PROFILER_TIMEOUT_SECONDS
      ).stdout
      return nil if json_text.nil? || json_text.strip.empty?

      net_data = JSON.parse(json_text)
      nets = net_data['SPNetworkDataType']
      return nil if nets.nil? || nets.empty?

      detect_wifi_interface_from_profiler_networks(nets)
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

    private def wifi_interface_airport_data(timeout_in_secs: nil, deadline: nil)
      data = airport_data(timeout_in_secs: deadline ? status_timeout_for(deadline) : timeout_in_secs)
      airport_interfaces = data.dig('SPAirPortDataType', 0, 'spairport_airport_interfaces')
      return nil unless airport_interfaces

      iface = deadline ? status_wifi_interface(deadline) : wifi_interface
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

    private def status_associated_without_ssid?(deadline)
      iface = status_wifi_interface(deadline)
      return false unless iface
      return true if status_default_interface(deadline) == iface

      !status_ip_address(deadline).nil?
    rescue WifiWand::CommandExecutor::OsCommandError
      false
    end

    private def status_network_name_from_airport_data(wifi_interface_data)
      current_network = wifi_interface_data&.fetch('spairport_current_network_information', nil)
      return nil unless current_network

      network_name = current_network.is_a?(Hash) ? current_network['_name'] : current_network
      placeholder_network_name?(network_name) ? nil : network_name
    end

    private def wifi_on_before_deadline?(deadline)
      iface = status_wifi_interface(deadline)
      return false unless iface

      output = run_command_using_args(
        ['networksetup', '-getairportpower', iface],
        timeout_in_secs: status_timeout_for(deadline)
      ).stdout
      output.chomp.match?(/\): On$/)
    end

    private def status_wifi_interface(deadline)
      return @wifi_interface if @wifi_interface

      @wifi_interface = probe_wifi_interface(timeout_in_secs: status_timeout_for(deadline))
    end

    private def status_default_interface(deadline)
      output = run_command_using_args(
        %w[route -n get default],
        raise_on_error:  false,
        timeout_in_secs: status_timeout_for(deadline)
      ).stdout
      return nil if output.empty?

      interface_line = output.split("\n").find { |line| line.include?('interface:') }
      return nil unless interface_line

      interface_line.split(':', 2).last.strip
    end

    private def status_ip_address(deadline)
      iface = status_wifi_interface(deadline)
      return nil unless iface

      ip_address = run_command_using_args(
        ['ipconfig', 'getifaddr', iface],
        timeout_in_secs: status_timeout_for(deadline)
      ).stdout.chomp
      ip_address.empty? ? nil : ip_address
    rescue WifiWand::CommandExecutor::OsCommandError => e
      raise unless e.exitstatus == 1

      nil
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
      context = enter_airport_data_cache_scope
      yield
    ensure
      exit_airport_data_cache_scope(context) if context
    end

    private def enter_airport_data_cache_scope
      context = active_airport_data_cache_context

      if context
        context[:depth] += 1
      else
        context = { depth: 1 }
        airport_data_cache_contexts[self] = context
      end

      context
    end

    private def exit_airport_data_cache_scope(context)
      context[:depth] -= 1
      return if context[:depth].positive?

      contexts = current_airport_data_cache_contexts
      contexts&.delete(self)
      Thread.current[AIRPORT_DATA_CACHE_CONTEXTS_KEY] = nil if contexts&.empty?
    end

    private def active_airport_data_cache_context
      current_airport_data_cache_contexts&.fetch(self, nil)
    end

    private def current_airport_data_cache_contexts
      Thread.current[AIRPORT_DATA_CACHE_CONTEXTS_KEY]
    end

    private def airport_data_cache_contexts
      Thread.current[AIRPORT_DATA_CACHE_CONTEXTS_KEY] ||= {}.compare_by_identity
    end

    private def airport_data(timeout_in_secs: nil)
      context = active_airport_data_cache_context
      generation = airport_data_cache_generation
      return context[:data] if cached_airport_data_current?(context, generation)

      json_text = run_command_using_args(
        SYSTEM_PROFILER_AIRPORT_ARGS,
        raise_on_error:  true,
        timeout_in_secs: timeout_in_secs || SYSTEM_PROFILER_TIMEOUT_SECONDS
      ).stdout
      begin
        parsed_data = JSON.parse(json_text)
      rescue JSON::ParserError => e
        raise SystemProfilerError, "Failed to parse system_profiler output: #{e.message}"
      end

      cache_airport_data(context, generation, parsed_data)
      parsed_data
    end

    private def invalidate_airport_data_cache
      @airport_data_cache_mutex.synchronize do
        @airport_data_cache_generation += 1
      end

      context = active_airport_data_cache_context
      return unless context

      context.delete(:data)
      context.delete(:generation)
    end

    private def airport_data_cache_generation
      @airport_data_cache_mutex.synchronize { @airport_data_cache_generation }
    end

    private def cached_airport_data_current?(context, generation)
      context&.key?(:data) && context[:generation] == generation
    end

    private def cache_airport_data(context, generation, parsed_data)
      return unless context
      return unless generation == airport_data_cache_generation

      context[:data] = parsed_data
      context[:generation] = generation
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
        preferred_networks = wifi_interface_data[network_list_key(wifi_interface_data)] || []
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
