# frozen_string_literal: true

require 'json'
require 'ipaddr'
require 'net/http'
require 'openssl'
require 'shellwords'
require 'socket'
require 'tempfile'
require 'uri'
require_relative 'helpers/command_output_formatter'
require_relative 'helpers/resource_manager'
require_relative 'helpers/qr_code_generator'
require_relative '../errors'
require_relative '../connectivity_states'
require_relative '../services/command_executor'
require_relative '../services/network_connectivity_tester'
require_relative '../services/network_state_manager'
require_relative '../services/status_waiter'
require_relative '../services/connection_manager'
require_relative '../services/status_line_data_builder'

module WifiWand
  class BaseModel
    attr_writer :wifi_interface
    attr_accessor :verbose_mode, :command_executor, :connectivity_tester, :state_manager,
      :status_waiter, :connection_manager

    def self.create_model(options = {})
      options = OpenStruct.new(options) if options.is_a?(Hash)
      instance = new(options)
      # Eagerly validate an explicitly-specified interface; defer discovery otherwise.
      instance.init if options.respond_to?(:wifi_interface) && options.wifi_interface
      instance
    end

    def self.current_os_matches_this_model?
      WifiWand::OperatingSystems.current_os&.id == os_id
    end

    def initialize(options = {})
      options = OpenStruct.new(options) if options.is_a?(Hash)
      @options = options
      @verbose_mode = options.verbose
      # Store the original output stream option, but use a dynamic method for out_stream
      @original_out_stream = options.respond_to?(:out_stream) && options.out_stream
      @command_executor = CommandExecutor.new(verbose: @verbose_mode, output: out_stream)
      @connectivity_tester = NetworkConnectivityTester.new(verbose: @verbose_mode, output: out_stream)
      @state_manager = NetworkStateManager.new(self, verbose: @verbose_mode, output: out_stream)
      @status_waiter = StatusWaiter.new(self, verbose: @verbose_mode, output: out_stream)
      @connection_manager = ConnectionManager.new(self, verbose: @verbose_mode)
    end

    # Dynamic output stream that respects current $stdout (for test silence_output compatibility)
    def out_stream = @original_out_stream || $stdout

    # Returns a symbol identifying the operating system for this model
    # Examples: :mac, :ubuntu
    def os = self.class.os_id

    # Convenience OS predicates
    def mac? = os == :mac

    def ubuntu? = os == :ubuntu

    def init
      init_wifi_interface
      self
    end

    def init_wifi_interface
      validate_os_preconditions

      # Initialize WiFi interface (e.g.: "wlp0s20f3")
      if @options.wifi_interface
        if is_wifi_interface?(@options.wifi_interface)
          @wifi_interface = @options.wifi_interface
        else
          raise InvalidInterfaceError, @options.wifi_interface
        end
      else
        @wifi_interface = probe_wifi_interface
      end

      # Validate that WiFi interface is a valid string
      if @wifi_interface.nil? || @wifi_interface.empty?
        raise WifiInterfaceError
      end

      self
    end

    # Returns the WiFi interface, initializing it lazily when needed.
    def wifi_interface
      init_wifi_interface if @wifi_interface.nil?
      @wifi_interface
    end

    # @return array of nameserver IP addresses from /etc/resolv.conf, or nil if not found
    # This is the fallback method that works on most Unix-like systems
    def nameservers_using_resolv_conf
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end

    # Define methods that must be implemented by subclasses in order to be called successfully:
    def self.define_subclass_required_method(method_name)
      define_method(method_name) do
        raise NotImplementedError, "Subclasses must implement #{method_name}"
      end
    end

    # Methods that subclasses must implement but are called via wrapper methods
    UNDERSCORE_PREFIXED_METHODS = %i[
      _available_network_names
      _connected_network_name
      _connect
      _disconnect
      _ip_address
      _preferred_network_password
    ].freeze

    REQUIRED_OVERRIDE_METHODS = %i[
      connected?
      connection_security_type
      default_interface
      is_wifi_interface?
      mac_address
      nameservers
      network_hidden?
      open_resource
      probe_wifi_interface
      preferred_networks
      remove_preferred_network
      set_nameservers
      validate_os_preconditions
      wifi_off
      wifi_on
      wifi_on?
    ].freeze

    REQUIRED_SUBCLASS_METHODS = (UNDERSCORE_PREFIXED_METHODS + REQUIRED_OVERRIDE_METHODS).freeze
    PUBLIC_IP_TIMEOUT_IN_SECONDS = 2
    COUNTRY_CODE_REGEX = /\A[A-Z]{2}\z/

    def self.subclass_implements_method?(subclass, method_name)
      subclass.instance_method(method_name).owner != BaseModel
    rescue NameError
      false
    end

    # Verify that a subclass implements all required methods and overrides
    # BaseModel placeholders for public API methods.
    def self.verify_required_methods_implemented(subclass)
      missing_methods = REQUIRED_SUBCLASS_METHODS.reject do |method_name|
        subclass_implements_method?(subclass, method_name)
      end

      unless missing_methods.empty?
        raise NotImplementedError, "Subclass #{subclass.name} must implement #{missing_methods.inspect}"
      end
    end

    # Automatically verify underscore methods when a subclass is inherited
    def self.inherited(subclass)
      trace = TracePoint.new(:end) do |tp|
        if tp.self == subclass
          verify_required_methods_implemented(subclass)
          trace.disable
        end
      end
      trace.enable
    end

    REQUIRED_OVERRIDE_METHODS.each { |method_name| define_subclass_required_method(method_name) }

    def available_network_names
      raise WifiOffError, 'WiFi is off, cannot scan for available networks.' unless wifi_on?

      _available_network_names
    end

    def connected_network_name
      raise WifiOffError, 'WiFi is off, cannot determine connected network.' unless wifi_on?

      _connected_network_name
    end

    # Returns true when WiFi is on and the interface is associated with an SSID.
    # Returns false when WiFi is off or there is no active SSID association.
    def associated?
      name = connected_network_name
      !name.nil? && !name.empty?
    rescue WifiWand::Error
      false
    end

    def disconnect
      return nil unless wifi_on?
      return nil unless associated?

      # Capture the SSID before asking the OS to disconnect so timeout handling
      # can still report which network we expected to leave.
      original_network_name = connected_network_name
      _disconnect
      # A disconnect only counts as success once the interface actually reports
      # no active association, mirroring the postcondition checks used elsewhere.
      till(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      # On some systems the SSID can disappear briefly during state churn before
      # the radio re-associates. Require a short stable disassociation window so
      # a transient nil SSID does not count as a successful disconnect.
      raise WifiWand::WaitTimeoutError.new(:disassociated, disconnect_stability_window_in_secs) unless
        disassociated_stable?

      nil
    rescue WifiWand::WaitTimeoutError
      # Re-check the SSID after a timeout so callers get the best available
      # diagnostic when the disconnect command ran but the radio stayed associated.
      current_network_name = begin
        connected_network_name
      rescue WifiWand::Error
        nil
      end
      lingering_network_name = current_network_name || original_network_name
      reason = lingering_network_name ? "still associated with '#{lingering_network_name}'" :
        'interface remained associated'
      raise NetworkDisconnectionError.new(lingering_network_name, reason)
    end

    # Returns true when the model considers the requested network fully usable.
    # Subclasses may override this to require stronger OS-specific readiness.
    def disconnect_stability_window_in_secs
      WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL * 2
    end

    def disassociated_stable?
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + disconnect_stability_window_in_secs

      loop do
        return false if associated?
        return true if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL)
      end
    end

    def connection_ready?(network_name)
      connected? && connected_network_name == network_name
    rescue WifiWand::Error => e
      out_stream.puts("connection_ready? check failed: #{e.class}: #{e.message}") if @verbose_mode
      false
    end

    def ip_address
      raise Error, 'Cannot get IP address: not connected to a network.' unless connected?

      _ip_address
    end

    def run_os_command(command, raise_on_error = true)
      @command_executor.run_os_command(command, raise_on_error)
    end

    # Returns an explicit internet connectivity state:
    # :reachable, :unreachable, or :indeterminate.
    def internet_connectivity_state(tcp_working = nil, dns_working = nil,
      captive_portal_state = NetworkConnectivityTester::UNSET)
      debug_method_entry(__method__)
      @connectivity_tester.internet_connectivity_state(tcp_working, dns_working, captive_portal_state)
    end

    # Tests TCP connectivity to internet hosts (not localhost)
    def internet_tcp_connectivity?
      debug_method_entry(__method__)
      @connectivity_tester.tcp_connectivity?
    end

    # Tests DNS resolution capability
    def dns_working?
      debug_method_entry(__method__)
      @connectivity_tester.dns_working?
    end

    # Returns an explicit captive-portal state: :free, :present, or :indeterminate.
    def captive_portal_state
      debug_method_entry(__method__)
      @connectivity_tester.captive_portal_state
    end

    # Fast connectivity check optimized for continuous monitoring (e.g. `log` and `status` commands).
    # Returns true if any of 3 geographically diverse endpoints is reachable within 1 second.
    # Skips DNS checking (often cached). Ideal for outage detection.
    def fast_connectivity?
      debug_method_entry(__method__)
      @connectivity_tester.fast_connectivity?
    end

    EXPECTED_NETWORK_ERRORS = [
      SocketError,
      IOError,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Timeout::Error,
    ].freeze

    # Returns comprehensive WiFi information including connectivity details
    def wifi_info
      debug_method_entry(__method__)
      internet_tcp = begin
        internet_tcp_connectivity?
      rescue *EXPECTED_NETWORK_ERRORS, WifiWand::Error
        false
      end

      dns_working = begin
        dns_working?
      rescue *EXPECTED_NETWORK_ERRORS, WifiWand::Error
        false
      end

      portal_state = if internet_tcp && dns_working
        begin
          captive_portal_state
        rescue *EXPECTED_NETWORK_ERRORS, WifiWand::Error
          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
        end
      else
        ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
      end

      # Pass all pre-computed values to avoid redundant network calls
      connectivity_state = ConnectivityStates.internet_state_from(
        tcp_working:          internet_tcp,
        dns_working:          dns_working,
        captive_portal_state: portal_state
      )

      {
        'wifi_on'                     => wifi_on?,
        'internet_tcp_connectivity'   => internet_tcp,
        'dns_working'                 => dns_working,
        'captive_portal_state'        => portal_state,
        'internet_connectivity_state' => connectivity_state,
        'interface'                   => wifi_interface,
        'default_interface'           => begin; default_interface; rescue WifiWand::Error; nil; end,
        'network'                     => begin; connected_network_name; rescue WifiWand::Error; nil; end,
        'ip_address'                  => begin; ip_address; rescue WifiWand::Error; nil; end,
        'mac_address'                 => begin; mac_address; rescue WifiWand::Error; nil; end,
        'nameservers'                 => begin; nameservers; rescue WifiWand::Error; []; end,
        'preferred_networks'          => begin; preferred_networks; rescue WifiWand::Error; []; end,
        'available_networks'          => begin; available_network_names; rescue WifiWand::Error; []; end,
        'timestamp'                   => Time.now,
      }
    end

    # Toggles WiFi on/off state twice; if on, turns off then on; else, turn on then off.
    def cycle_network
      debug_method_entry(__method__)
      if wifi_on?
        wifi_off
        wifi_on
      else
        wifi_on
        wifi_off
      end
    end

    # Builds a hash for the status command, yielding partial results as soon as
    # they're known so callers can stream updates.
    # Network identity and internet checks run concurrently in native threads so
    # blocking OS commands and socket work can overlap. Internet status uses the
    # full connectivity path so captive portals are reported as unreachable.
    # The returned hash includes :internet_state and :captive_portal_state
    # plus the derived :captive_portal_login_required (:yes/:no/:unknown).
    def status_line_data(progress_callback: nil)
      StatusLineDataBuilder.new(
        self,
        verbose:                 @verbose_mode,
        output:                  out_stream,
        expected_network_errors: EXPECTED_NETWORK_ERRORS
      ).call(progress_callback: progress_callback)
    end

    def connected_to?(network_name)
      debug_method_entry(__method__, binding, :network_name)
      network_name == connected_network_name
    end

    # Connects to the passed network name, optionally with password.
    # Delegates to ConnectionManager for complex connection logic.
    def connect(network_name, password = nil, skip_saved_password_lookup: false)
      debug_method_entry(__method__, binding, %i[network_name password])
      @connection_manager.connect(network_name, password,
        skip_saved_password_lookup: skip_saved_password_lookup)
    end

    # Removes the specified network(s) from the preferred network list.
    # @param network_names names of networks to remove; may be empty or contain nonexistent networks
    #        can be a single arg which is an array of names or 1 name string per arg
    # @return names of the networks that were removed (excludes non-preexisting networks)
    def remove_preferred_networks(*network_names)
      network_names = network_names.first if network_names.first.is_a?(Array) && network_names.size == 1
      network_names = network_names.map(&:to_s)

      network_names.select { |name| has_preferred_network?(name) }
        .flat_map do |name|
          removed_names = Array(remove_preferred_network(name))
          removed_names.empty? ? [name] : removed_names
        end
        .uniq
    end

    def preferred_network_password(preferred_network_name)
      debug_method_entry(__method__, binding, :preferred_network_name)
      preferred_network_name = preferred_network_name.to_s
      if has_preferred_network?(preferred_network_name)
        _preferred_network_password(preferred_network_name)
      else
        raise PreferredNetworkNotFoundError, preferred_network_name
      end
    end

    # Returns true if the given network name exists in the preferred networks list.
    # Extracted for easier testing and overriding/mocking.
    def has_preferred_network?(network_name) = preferred_networks.include?(network_name.to_s)

    # Waits for the WiFi/Internet state to reach target_status.
    # @param target_status one of StatusWaiter::PERMITTED_STATES:
    #   :wifi_on / :wifi_off         – WiFi hardware power state
    #   :associated / :disassociated – WiFi SSID association state
    #   :internet_on / :internet_off – full Internet reachability (TCP + DNS + captive-portal free)
    # @param timeout_in_secs after this many seconds the method will raise a WaitTimeoutError;
    #        if nil (default), waits indefinitely
    # @param wait_interval_in_secs sleeps this interval between retries; if nil or absent,
    #        a default will be provided
    def till(target_status, timeout_in_secs: nil, wait_interval_in_secs: nil,
      stringify_permitted_values_in_error_msg: false)
      debug_method_entry(__method__, binding, %i[target_status timeout_in_secs wait_interval_in_secs])

      @status_waiter.wait_for(
        target_status,
        timeout_in_secs:                         timeout_in_secs,
        wait_interval_in_secs:                   wait_interval_in_secs,
        stringify_permitted_values_in_error_msg: stringify_permitted_values_in_error_msg
      )
    end

    # Tries an OS command until the stop condition is true.
    # @command the command to run in the OS
    # @stop_condition a lambda taking the command's stdout as its sole parameter
    # @return the stdout produced by the command, or nil if max_tries was reached
    def try_os_command_until(command, stop_condition, max_tries = 100)
      debug_method_entry(__method__, binding, %i[command stop_condition max_tries])

      @command_executor.try_os_command_until(command, stop_condition, max_tries)
    end

    def public_ip_info
      uri = URI.parse('https://api.country.is/')
      response = public_ip_http_get(uri)
      parsed = JSON.parse(response.body)

      address = parsed['ip'].to_s.strip
      country = parsed['country'].to_s.strip.upcase

      unless valid_public_ip_address?(address) && country.match?(COUNTRY_CODE_REGEX)
        raise WifiWand::PublicIPLookupError.new(
          message: 'Public IP lookup failed: malformed response',
          url:     uri.to_s,
          body:    response.body
        )
      end

      { 'address' => address, 'country' => country }
    rescue JSON::ParserError
      raise WifiWand::PublicIPLookupError.new(
        message: 'Public IP lookup failed: malformed response',
        url:     uri.to_s,
        body:    response&.body
      )
    end

    def public_ip_address
      uri = URI.parse('https://api.ipify.org')
      response = public_ip_http_get(uri)
      address = response.body.to_s.strip

      if valid_public_ip_address?(address)
        address
      else
        raise WifiWand::PublicIPLookupError.new(
          message: 'Public IP lookup failed: malformed response',
          url:     uri.to_s,
          body:    response.body
        )
      end
    end

    def public_ip_country = public_ip_info.fetch('country')

    def random_mac_address
      bytes = Array.new(6) { rand(256) }
      # Ensure first byte is locally administered unicast:
      # - Clear multicast bit (bit 0) with mask 0xFE
      # - Set locally administered bit (bit 1) with OR 0x02
      bytes[0] = (bytes[0] & 0xFE) | 0x02
      chars = bytes.map { |b| format('%02x', b) }
      chars.join(':')
    end

    # Resource management functionality
    def resource_manager = @resource_manager ||= Helpers::ResourceManager.new

    def open_resources_by_codes(*resource_codes)
      resource_manager.open_resources_by_codes(self, *resource_codes)
    end

    def available_resources_help = resource_manager.available_resources_help

    # QR code generator helper
    def qr_code_generator = @qr_code_generator ||= Helpers::QrCodeGenerator.new

    # Network State Management for Testing
    # These methods help capture and restore network state during disruptive tests

    def capture_network_state
      debug_method_entry(__method__)

      @state_manager.capture_network_state
    end

    def restore_network_state(state, fail_silently: false)
      debug_method_entry(__method__, binding, %i[state fail_silently])
      @state_manager.restore_network_state(state, fail_silently: fail_silently)
    end

    # Returns true if the last connection attempt used a saved password.
    def last_connection_used_saved_password?
      debug_method_entry(__method__)

      @connection_manager.last_connection_used_saved_password?
    end

    # Generates a QR code for the currently connected WiFi network
    # @return [String] The filename of the generated QR code PNG file
    # @raise [WifiWand::Error] If not connected to a network or qrencode is not available
    def generate_qr_code(filespec = nil, overwrite: false, delivery_mode: :print, password: nil,
      in_stream: $stdin)
      debug_method_entry(__method__)
      qr_code_generator.generate(self, filespec, overwrite: overwrite, delivery_mode: delivery_mode,
        password: password, in_stream: in_stream)
    end

    private

    def valid_public_ip_address?(address)
      IPAddr.new(address)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def public_ip_http_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.read_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.write_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS if http.respond_to?(:write_timeout=)

      response = http.request(Net::HTTP::Get.new(uri.request_uri))
      return response if response.is_a?(Net::HTTPSuccess)

      if response.code == '429'
        raise WifiWand::PublicIPLookupError.new(
          message: 'Public IP lookup failed: rate limited',
          url:     uri.to_s
        )
      end

      raise WifiWand::PublicIPLookupError.new(
        message: "Public IP lookup failed: HTTP #{response.code} #{response.message}",
        url:     uri.to_s
      )
    rescue Timeout::Error, Errno::ETIMEDOUT
      raise WifiWand::PublicIPLookupError.new(
        message: 'Public IP lookup failed: timeout',
        url:     uri.to_s
      )
    rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise WifiWand::PublicIPLookupError.new(
        message: 'Public IP lookup failed: network error',
        url:     uri.to_s
      )
    end

    # Normalizes a raw security descriptor string from OS tools to
    # one of: "WPA3", "WPA2", "WPA", "WEP", or nil (unknown/open/enterprise).
    # This centralizes regex handling across OS implementations.
    def canonical_security_type_from(security_text)
      return nil if security_text.nil?

      text = security_text.to_s.strip
      return nil if text.empty?

      # Exclude enterprise/EAP networks which are not representable with PSK/WEP
      return nil if text.match?(/802\.?1x|enterprise/i)

      case text
      when /WPA3/i
        'WPA3'
      when /WPA2/i
        'WPA2'
      when /WPA1/i, /WPA(?!\d)/i
        'WPA'
      when /WEP/i
        'WEP'
      end
    end

    def connected_network_password
      debug_method_entry(__method__)
      network_name = connected_network_name
      return nil unless network_name

      preferred_network_password(network_name)
    end

    def command_available?(command) = @command_executor.command_available?(command)

    # Emits a verbose method-entry trace for debugging.
    #
    # When caller_binding and param_names are provided, the named local variables are
    # read from the caller binding and included in the formatted output.
    #
    # Example:
    #   debug_method_entry(__method__, binding, %i[network_name password])
    #
    # @param method_name [String, Symbol] the method being entered
    # @param caller_binding [Binding, nil] caller binding used to resolve parameter values
    # @param param_names [Symbol, Array<Symbol>, nil] local variable names to include
    # @return [void]
    def debug_method_entry(method_name, caller_binding = nil, param_names = nil)
      return unless verbose_mode

      s = "Entered #{self.class.name.split('::').last}##{method_name}"
      param_names = Array(param_names) # force to array if passed a single symbol
      if param_names
        values = param_names.map { |name| caller_binding.local_variable_get(name) }
        s += "(#{values.map(&:to_s).map(&:inspect).join(', ')})"
      end
      out_stream.puts s
    end
  end
end
