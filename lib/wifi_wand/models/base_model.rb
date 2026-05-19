# frozen_string_literal: true

require 'json'
require 'ipaddr'
require 'net/http'
require 'openssl'
require 'shellwords'
require 'socket'
require 'tempfile'
require 'uri'
require_relative 'helpers/resource_manager'
require_relative 'helpers/qr_code_generator'
require_relative '../errors'
require_relative '../runtime_config'
require_relative '../connectivity_states'
require_relative '../network_identity'
require_relative '../signal_quality'
require_relative '../string_predicates'
require_relative '../services/command_executor'
require_relative '../services/network_connectivity_tester'
require_relative '../services/network_state_manager'
require_relative '../services/status_waiter'
require_relative '../services/connection_manager'
require_relative '../services/status_line_data_builder'

module WifiWand
  class BaseModel
    include StringPredicates

    Options = Struct.new(:verbose, :utc, :wifi_interface, :out_stream, :err_stream, keyword_init: true)

    attr_writer :wifi_interface
    attr_reader :runtime_config
    attr_accessor :command_executor, :connectivity_tester, :state_manager, :status_waiter, :connection_manager

    def self.create_model(options = {})
      normalized_options = normalize_create_model_options(options)
      instance = new(normalized_options)
      # Eagerly validate an explicitly-specified interface; defer discovery otherwise.
      instance.init if normalized_options.wifi_interface
      instance
    end

    def self.current_os_matches_this_model?
      WifiWand::Platforms::Selector.current_os&.id == os_id
    end

    def initialize(options = {})
      verify_subclass_contract

      options = normalize_constructor_options(options)
      @options = options
      @runtime_config = RuntimeConfig.new(
        verbose:    options.verbose,
        utc:        options.utc || false,
        out_stream: options.out_stream || $stdout,
        err_stream: options.err_stream || $stderr
      )
      @command_executor = CommandExecutor.new(runtime_config: @runtime_config)
      @connectivity_tester = NetworkConnectivityTester.new(runtime_config: @runtime_config)
      @state_manager = NetworkStateManager.new(self, runtime_config: @runtime_config)
      @status_waiter = StatusWaiter.new(self, runtime_config: @runtime_config)
      @connection_manager = ConnectionManager.new(self, runtime_config: @runtime_config)
    end

    def out_stream = runtime_config.out_stream

    def out_stream=(stream)
      runtime_config.out_stream = stream
    end

    def err_stream = runtime_config.err_stream

    def verbose? = runtime_config.verbose

    def verbose=(value)
      runtime_config.verbose = !!value
    end

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
      if string_nil_or_empty?(@wifi_interface)
        raise WifiInterfaceError
      end

      self
    end

    # Returns the WiFi interface, initializing it lazily when needed.
    def wifi_interface
      init_wifi_interface if @wifi_interface.nil?
      @wifi_interface
    end

    def self.normalize_create_model_options(options)
      raise ArgumentError, 'options must be a Hash' unless options.is_a?(Hash)

      Options.new(**options)
    end

    private_class_method :normalize_create_model_options

    private def normalize_constructor_options(options)
      return Options.new(**options) if options.is_a?(Hash)
      return options if options.is_a?(Options)

      raise ArgumentError, 'options must be a Hash or WifiWand::BaseModel::Options'
    end

    # @return array of nameserver IP addresses from /etc/resolv.conf, or nil if not found
    # This is the fallback method that works on most Unix-like systems
    def nameservers_using_resolv_conf
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end

    REQUIRED_SUBCLASS_METHODS = {
      _available_network_names:    :any_visibility,
      _connected_network_name:     :any_visibility,
      _connect:                    :any_visibility,
      _disconnect:                 :any_visibility,
      _ipv4_addresses:             :any_visibility,
      _ipv6_addresses:             :any_visibility,
      _preferred_network_password: :any_visibility,
      bssid:                       :public,
      connected?:                  :public,
      connection_security_type:    :public,
      default_interface:           :public,
      is_wifi_interface?:          :public,
      mac_address:                 :public,
      nameservers:                 :public,
      network_hidden?:             :public,
      open_resource:               :public,
      probe_wifi_interface:        :public,
      preferred_networks:          :public,
      remove_preferred_network:    :public,
      set_nameservers:             :public,
      signal_quality:              :public,
      validate_os_preconditions:   :public,
      wifi_off:                    :public,
      wifi_on:                     :public,
      wifi_on?:                    :public,
    }.freeze

    PUBLIC_IP_TIMEOUT_IN_SECONDS = 3
    PUBLIC_IP_MAX_ATTEMPTS = 3
    PUBLIC_IP_RETRY_BASE_DELAY_IN_SECONDS = 0.2
    COUNTRY_CODE_REGEX = /\A[A-Z]{2}\z/

    def self.subclass_overrides_method?(subclass, method_name)
      method = if subclass.method_defined?(method_name) || subclass.private_method_defined?(method_name)
        subclass.instance_method(method_name)
      end

      method && method.owner != BaseModel
    end

    def self.subclass_publicly_overrides_method?(subclass, method_name)
      method = if subclass.public_method_defined?(method_name)
        subclass.public_instance_method(method_name)
      end

      method && method.owner != BaseModel
    end

    def self.subclass_implements_required_method?(subclass, method_name, required_visibility)
      case required_visibility
      when :public
        subclass_publicly_overrides_method?(subclass, method_name)
      when :any_visibility
        subclass_overrides_method?(subclass, method_name)
      else
        raise ArgumentError, "Unknown required method visibility: #{required_visibility.inspect}"
      end
    end

    # Verify that a subclass implements every required method with the required visibility.
    def self.verify_required_methods_implemented(subclass)
      missing_methods = REQUIRED_SUBCLASS_METHODS.reject do |method_name, required_visibility|
        subclass_implements_required_method?(subclass, method_name, required_visibility)
      end.keys

      unless missing_methods.empty?
        subclass_name = subclass.name || '(anonymous)'
        raise NotImplementedError, "Subclass #{subclass_name} must implement #{missing_methods.inspect}"
      end
    end

    # Automatically verify required method overrides when a subclass is inherited
    def self.inherited(subclass)
      super

      trace = TracePoint.new(:end) do |tp|
        if tp.self == subclass
          verify_required_methods_implemented(subclass)
          trace.disable
        end
      end
      trace.enable
    end

    private def verify_subclass_contract
      return if instance_of?(BaseModel)

      self.class.verify_required_methods_implemented(self.class)
    end
    private def raise_override_not_implemented_error(method_name)
      raise NotImplementedError, "Subclasses must implement #{method_name}"
    end

    def connected? = raise_override_not_implemented_error(__method__)

    def bssid = raise_override_not_implemented_error(__method__)

    def signal_quality = raise_override_not_implemented_error(__method__)

    def connection_security_type = raise_override_not_implemented_error(__method__)

    def default_interface = raise_override_not_implemented_error(__method__)

    def is_wifi_interface?(_interface_name) = raise_override_not_implemented_error(__method__)

    def mac_address = raise_override_not_implemented_error(__method__)

    def nameservers = raise_override_not_implemented_error(__method__)

    def network_hidden? = raise_override_not_implemented_error(__method__)

    def open_resource(_resource) = raise_override_not_implemented_error(__method__)

    def probe_wifi_interface = raise_override_not_implemented_error(__method__)

    def preferred_networks = raise_override_not_implemented_error(__method__)

    def remove_preferred_network(_network_name) = raise_override_not_implemented_error(__method__)

    def set_nameservers(_nameservers) = raise_override_not_implemented_error(__method__) # rubocop:disable Naming/AccessorMethodName

    def validate_os_preconditions = raise_override_not_implemented_error(__method__)

    def wifi_off = raise_override_not_implemented_error(__method__)

    def wifi_on = raise_override_not_implemented_error(__method__)

    def wifi_on? = raise_override_not_implemented_error(__method__)

    def available_network_names
      raise WifiOffError, 'WiFi is off, cannot scan for available networks.' unless wifi_on?

      _available_network_names
    end

    def available_network_scan
      raise WifiOffError, 'WiFi is off, cannot scan for available networks.' unless wifi_on?

      successful_available_network_scan(_available_network_names)
    end

    def connected_network_name
      raise WifiOffError, 'WiFi is off, cannot determine connected network.' unless wifi_on?

      _connected_network_name
    end

    def status_wifi_on?(timeout_in_secs: nil)
      if timeout_in_secs
        raise MethodNotImplementedError,
          'Subclasses must implement bounded status_wifi_on?(timeout_in_secs:)'
      end

      wifi_on?
    end

    def status_network_identity(timeout_in_secs: nil)
      if timeout_in_secs
        raise MethodNotImplementedError,
          'Subclasses must implement bounded status_network_identity(timeout_in_secs:)'
      end

      connected = connected?
      network_name = connected ? connected_network_name : nil

      {
        connected:      connected,
        network_name:   network_name,
        signal_quality: connected ? signal_quality : nil,
      }
    end

    private def status_deadline(timeout_in_secs)
      monotonic_now + timeout_in_secs if timeout_in_secs
    end

    private def status_timeout_for(deadline)
      return nil unless deadline

      [deadline - monotonic_now, 0].max
    end

    private def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Returns true when WiFi is on and the interface is associated with an SSID.
    # Returns false when WiFi is off or there is no active SSID association.
    def associated?
      name = connected_network_name
      !name.nil? && !name.empty?
    rescue WifiWand::Error
      false
    end

    def disconnect
      original_network_name = nil
      return nil unless wifi_on?

      # Capture the SSID before asking the OS to disconnect so timeout handling
      # can still report which network we expected to leave.
      association_state = disconnect_association_state
      original_network_name = association_state.fetch(:network_name)
      return nil unless association_state.fetch(:associated)

      _disconnect
      # A disconnect only counts as success once the interface actually reports
      # no active association, mirroring the postcondition checks used elsewhere.
      wait_until_disassociated!(timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
      # On some systems the SSID can disappear briefly during state churn before
      # the radio re-associates. Require a short stable disassociation window so
      # a transient nil SSID does not count as a successful disconnect.
      unless disassociated_stable?
        raise(WifiWand::WaitTimeoutError.new(
          action:  :disassociated,
          timeout: disconnect_stability_window_in_secs
        ))
      end

      nil
    rescue *NETWORK_OPERATION_COMMAND_ERRORS => e
      raise(disconnect_command_failure(original_network_name, e))
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
      raise(NetworkDisconnectionError.new(network_name: lingering_network_name, reason: reason))
    end

    # Returns true when the model considers the requested network fully usable.
    # Subclasses may override this to require stronger OS-specific readiness.
    def disconnect_stability_window_in_secs
      WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL * 2
    end

    def disassociated_stable?
      deadline = monotonic_now + disconnect_stability_window_in_secs

      loop do
        return false if disconnect_association_state.fetch(:associated)
        return true if monotonic_now >= deadline

        sleep(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL)
      end
    end

    def connection_ready?(network_name)
      connected? && connected_network_name == network_name
    rescue WifiWand::MacOsRedactionError
      raise
    rescue WifiWand::Error => e
      out_stream.puts("connection_ready? check failed: #{e.class}: #{e.message}") if verbose?
      false
    end

    def ipv4_addresses
      raise Error, 'Cannot get IPv4 addresses: not connected to a network.' unless connected?

      _ipv4_addresses
    end

    def ipv6_addresses
      raise Error, 'Cannot get IPv6 addresses: not connected to a network.' unless connected?

      _ipv6_addresses
    end

    def run_command(command, raise_on_error: true, timeout_in_secs: nil)
      @command_executor.run_command_using_args(command, raise_on_error: raise_on_error,
        timeout_in_secs: timeout_in_secs)
    end

    # Returns an explicit internet connectivity state:
    # :reachable, :unreachable, or :indeterminate.
    def internet_connectivity_state(tcp_working = nil, dns_working = nil,
      captive_portal_login_required = NetworkConnectivityTester::UNSET, timeout_in_secs: nil)
      debug_method_entry(__method__)
      @connectivity_tester.internet_connectivity_state(
        tcp_working,
        dns_working,
        captive_portal_login_required,
        timeout_in_secs: timeout_in_secs
      )
    end

    # Tests TCP connectivity to internet hosts (not localhost)
    def internet_tcp_connectivity?(timeout_in_secs: nil, return_details: false)
      debug_method_entry(__method__)
      @connectivity_tester.tcp_connectivity?(
        timeout_in_secs: timeout_in_secs || TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        return_details:  return_details
      )
    end

    # Tests DNS resolution capability
    def dns_working?(timeout_in_secs: nil, return_details: false)
      debug_method_entry(__method__)
      @connectivity_tester.dns_working?(
        timeout_in_secs: timeout_in_secs || TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        return_details:  return_details
      )
    end

    # Returns whether captive portal login appears to be required now: :yes, :no, or :unknown.
    def captive_portal_login_required(timeout_in_secs: nil)
      debug_method_entry(__method__)
      @connectivity_tester.captive_portal_login_required(timeout_in_secs: timeout_in_secs)
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

    NETWORK_OPERATION_COMMAND_ERRORS = [
      WifiWand::CommandExecutor::OsCommandError,
      WifiWand::CommandTimeoutError,
      WifiWand::CommandNotFoundError,
      WifiWand::CommandSpawnError,
    ].freeze

    # Returns comprehensive WiFi information including connectivity details
    def wifi_info
      debug_method_entry(__method__)
      connectivity = wifi_info_connectivity
      internet_tcp = connectivity.fetch(:internet_tcp)
      dns_working = connectivity.fetch(:dns_working)
      portal_login_required = connectivity.fetch(:portal_login_required)

      # Pass all pre-computed values to avoid redundant network calls
      connectivity_state = ConnectivityStates.internet_state_from_login_required(
        tcp_working:                   internet_tcp,
        dns_working:                   dns_working,
        captive_portal_login_required: portal_login_required
      )

      network_identity = wifi_info_network_identity

      {
        'wifi_on'                       => wifi_on?,
        'internet_tcp_connectivity'     => internet_tcp,
        'dns_working'                   => dns_working,
        'captive_portal_login_required' => portal_login_required,
        'internet_connectivity_state'   => connectivity_state,
        'interface'                     => wifi_interface,
        'default_interface'             => begin; default_interface; rescue WifiWand::Error; nil; end,
        'connected'                     => network_identity.fetch('connected'),
        'network'                       => network_identity.fetch('network'),
        'bssid'                         => begin; bssid; rescue WifiWand::Error; nil; end,
        'signal_quality'                => wifi_info_signal_quality,
        'ssid_identity_available'       => network_identity.fetch('ssid_identity_available'),
        'ssid_identity_status'          => network_identity.fetch('ssid_identity_status'),
        'ssid_identity_warning'         => network_identity.fetch('ssid_identity_warning'),
        'ipv4_addresses'                => wifi_info_ipv4_addresses,
        'ipv6_addresses'                => wifi_info_ipv6_addresses,
        'mac_address'                   => begin; mac_address; rescue WifiWand::Error; nil; end,
        'nameservers'                   => begin; nameservers; rescue WifiWand::Error; []; end,
        'timestamp'                     => Time.now,
      }
    end

    private def wifi_info_connectivity
      initial_probe_results = wifi_info_initial_connectivity_probe_results
      internet_tcp = initial_probe_results.fetch(:internet_tcp)
      dns_working = initial_probe_results.fetch(:dns_working)

      {
        internet_tcp:          internet_tcp,
        dns_working:           dns_working,
        portal_login_required: wifi_info_captive_portal_login_required(internet_tcp, dns_working),
      }
    end

    private def wifi_info_initial_connectivity_probe_results
      workers = {}
      result_queue = Queue.new
      workers[:internet_tcp] = wifi_info_probe_worker(result_queue, :internet_tcp) do
        internet_tcp_connectivity?
      end
      workers[:dns_working] = wifi_info_probe_worker(result_queue, :dns_working) { dns_working? }

      wifi_info_collect_probe_results(result_queue, workers)
    ensure
      workers.each_value(&:join)
    end

    private def wifi_info_probe_worker(result_queue, probe_name)
      Thread.new do
        result_queue << [probe_name, :result, yield]
      rescue *EXPECTED_NETWORK_ERRORS, WifiWand::Error
        result_queue << [probe_name, :result, false]
      rescue StandardError, ScriptError => e
        result_queue << [probe_name, :error, e]
      end
    end

    private def wifi_info_collect_probe_results(result_queue, workers)
      results = {}

      until results.length == workers.length
        probe_name, status, payload = wifi_info_next_probe_result(result_queue, workers, results)
        raise payload if status == :error

        results[probe_name] = payload
      end

      results
    end

    private def wifi_info_next_probe_result(result_queue, workers, results)
      loop do
        return result_queue.pop(true)
      rescue ThreadError
        probe_name, worker = workers.find { |name, thread| !results.key?(name) && !thread.alive? }

        if worker
          worker.value
          raise(WifiWand::Error, "WiFi info probe #{probe_name} exited without reporting a result")
        end

        sleep(0.01)
      end
    end

    private def wifi_info_captive_portal_login_required(internet_tcp, dns_working)
      return :unknown unless internet_tcp && dns_working

      captive_portal_login_required
    rescue *EXPECTED_NETWORK_ERRORS, WifiWand::Error
      :unknown
    end

    private def wifi_info_ipv4_addresses
      wifi_info_network_addresses(:ipv4_addresses)
    end

    private def wifi_info_signal_quality
      signal_quality&.to_h
    rescue WifiWand::Error
      nil
    end

    private def wifi_info_ipv6_addresses
      wifi_info_network_addresses(:ipv6_addresses)
    end

    private def wifi_info_network_addresses(method_name)
      public_send(method_name)
    rescue *NETWORK_OPERATION_COMMAND_ERRORS
      []
    rescue WifiWand::Error => e
      raise unless wifi_info_network_addresses_unavailable_error?(e)

      []
    end

    private def wifi_info_network_addresses_unavailable_error?(error)
      error.is_a?(WifiWand::WifiOffError) ||
        error.is_a?(WifiWand::WifiInterfaceError) ||
        (error.instance_of?(WifiWand::Error) && error.message.include?('not connected'))
    end

    private def successful_available_network_scan(networks)
      {
        'networks'          => Array(networks),
        'scan_status'       => 'ok',
        'scan_source'       => 'os',
        'ssid_data_trusted' => true,
        'warning'           => nil,
      }
    end

    private def wifi_info_network_identity
      connected = begin; connected?; rescue WifiWand::Error; nil; end
      warning = nil
      network_name = begin
        connected_network_name
      rescue WifiWand::MacOsRedactionError => e
        warning = e.message
        nil
      rescue WifiWand::Error
        nil
      end

      status = if NetworkIdentity.named?(network_name)
        'available'
      elsif connected == true
        'unavailable'
      elsif connected == false
        'not_connected'
      else
        'unknown'
      end

      {
        'connected'               => connected,
        'network'                 => network_name,
        'ssid_identity_available' => status == 'available',
        'ssid_identity_status'    => status,
        'ssid_identity_warning'   => warning,
      }
    end

    private def disconnect_association_state
      network_name = connected_network_name
      unless string_nil_or_empty?(network_name)
        return { associated: true, network_name: network_name }
      end

      # If the SSID is unavailable but the platform can still report an active
      # connection, try the disconnect instead of treating the operation as a
      # no-op. Unlike associated?, connected? does not intentionally collapse
      # command failures into false for this mutating preflight.
      {
        associated:   disconnect_associated?,
        network_name: nil,
      }
    rescue *NETWORK_OPERATION_COMMAND_ERRORS
      raise
    rescue WifiWand::MacOsRedactionError
      {
        associated:   disconnect_associated?,
        network_name: nil,
      }
    rescue WifiWand::Error
      # If the SSID cannot be read for a non-command reason, the safest
      # mutating behavior is to attempt the disconnect and let the
      # command/postcondition path determine the outcome.
      {
        associated:   true,
        network_name: nil,
      }
    end

    private def disconnect_associated?
      connected?
    end

    private def wait_until_disassociated!(timeout_in_secs:)
      deadline = monotonic_now + timeout_in_secs

      loop do
        return nil unless disconnect_association_state.fetch(:associated)

        remaining_time = deadline - monotonic_now
        raise(WaitTimeoutError.new(action: :disassociated, timeout: timeout_in_secs)) if remaining_time <= 0

        sleep([WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL, remaining_time].min)
      end
    end

    private def disconnect_command_failure(network_name, error)
      NetworkDisconnectionError.new(network_name: network_name, reason: command_error_detail(error))
    end

    private def command_error_detail(error)
      detail = error.display_message if error.respond_to?(:display_message)
      detail = error.message if string_nil_or_empty?(detail)
      detail.to_s
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
    # The returned hash includes :internet_state and
    # :captive_portal_login_required (:yes/:no/:unknown).
    def status_line_data(progress_callback: nil)
      StatusLineDataBuilder.call(
        self,
        progress_callback:       progress_callback,
        runtime_config:          runtime_config,
        expected_network_errors: EXPECTED_NETWORK_ERRORS
      )
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

    def preferred_network_password(preferred_network_name, timeout_in_secs: :default)
      debug_method_entry(__method__, binding, :preferred_network_name)
      preferred_network_name = preferred_network_name.to_s
      if has_preferred_network?(preferred_network_name)
        if timeout_in_secs == :default
          _preferred_network_password(preferred_network_name)
        else
          _preferred_network_password(preferred_network_name, timeout_in_secs: timeout_in_secs)
        end
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
    #   :internet_on / :internet_off – full Internet reachability (TCP + DNS + no captive-portal login)
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
    # Failed attempts are throttled by CommandExecutor to avoid tight process-spawn loops.
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
        raise(WifiWand::PublicIPLookupError.new(
          status_code:    nil,
          status_message: nil,
          message:        'Public IP lookup failed: malformed response',
          url:            uri.to_s,
          body:           response.body
        ))
      end

      { 'address' => address, 'country' => country }
    rescue JSON::ParserError
      raise(WifiWand::PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: malformed response',
        url:            uri.to_s,
        body:           response&.body
      ))
    end

    def public_ip_address
      uri = URI.parse('https://api.ipify.org')
      response = public_ip_http_get(uri)
      address = response.body.to_s.strip

      if valid_public_ip_address?(address)
        address
      else
        raise(WifiWand::PublicIPLookupError.new(
          status_code:    nil,
          status_message: nil,
          message:        'Public IP lookup failed: malformed response',
          url:            uri.to_s,
          body:           response.body
        ))
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

    # Returns true if the last completed connection used a saved password.
    # Failed or no-op connect() calls return false.
    def last_connection_used_saved_password?
      debug_method_entry(__method__)

      @connection_manager.last_connection_used_saved_password?
    end

    # Returns whether an operating system command is available on PATH.
    #
    # Helper objects that coordinate model behavior use this as part of the
    # model API instead of reaching into the command executor directly.
    def command_available?(command) = @command_executor.command_available?(command)

    # Generates a QR code for the currently connected WiFi network
    # @return [String] The filename of the generated QR code PNG file
    # @raise [WifiWand::Error] If not connected to a network or qrencode is not available
    def generate_qr_code(filespec = nil, overwrite: false, delivery_mode: :print, password: nil,
      in_stream: $stdin)
      debug_method_entry(__method__)
      qr_code_generator.generate(self, filespec, overwrite: overwrite, delivery_mode: delivery_mode,
        password: password, in_stream: in_stream)
    end

    private def valid_public_ip_address?(address)
      IPAddr.new(address)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    private def public_ip_http_get(uri)
      attempts = 0

      begin
        attempts += 1
        public_ip_http_get_once(uri)
      rescue WifiWand::PublicIPLookupError => e
        raise unless public_ip_retryable_error?(e)
        raise if attempts >= PUBLIC_IP_MAX_ATTEMPTS

        sleep(public_ip_retry_delay(attempts))
        retry
      end
    end

    private def public_ip_http_get_once(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.read_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS
      http.write_timeout = PUBLIC_IP_TIMEOUT_IN_SECONDS if http.respond_to?(:write_timeout=)

      response = http.request(Net::HTTP::Get.new(uri.request_uri))
      return response if response.is_a?(Net::HTTPSuccess)

      if response.code == '429'
        raise(WifiWand::PublicIPLookupError.new(
          status_code:    response.code,
          status_message: response.message,
          message:        'Public IP lookup failed: rate limited',
          url:            uri.to_s
        ))
      end

      raise(WifiWand::PublicIPLookupError.new(
        status_code:    response.code,
        status_message: response.message,
        message:        "Public IP lookup failed: HTTP #{response.code} #{response.message}",
        url:            uri.to_s
      ))
    rescue Timeout::Error, Errno::ETIMEDOUT
      raise(WifiWand::PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: timeout',
        url:            uri.to_s
      ))
    rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise(WifiWand::PublicIPLookupError.new(
        status_code:    nil,
        status_message: nil,
        message:        'Public IP lookup failed: network error',
        url:            uri.to_s
      ))
    end

    private def public_ip_retry_delay(attempts_completed)
      PUBLIC_IP_RETRY_BASE_DELAY_IN_SECONDS * (2**(attempts_completed - 1))
    end

    private def public_ip_retryable_error?(error)
      return true if error.status_code.nil?

      error.status_code.to_i >= 500
    end

    # Normalizes a raw security descriptor string from OS tools to
    # one of: "WPA3", "WPA2", "WPA", "WEP", "NONE", or nil (unknown/enterprise).
    # This centralizes regex handling across OS implementations.
    private def canonical_security_type_from(security_text)
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
      when /\bnone\b|spairport_security_mode_none/i, /\bowe\b/i
        'NONE'
      end
    end

    private def connected_network_password
      debug_method_entry(__method__)
      network_name = connected_network_name
      return nil unless network_name

      preferred_network_password(network_name)
    end

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
    private def debug_method_entry(method_name, caller_binding = nil, param_names = nil)
      return unless verbose?

      s = "Entered #{self.class.name.split('::').last}##{method_name}"
      param_names = Array(param_names) # force to array if passed a single symbol
      if param_names.any?
        values = param_names.map { |name| caller_binding.local_variable_get(name) }
        s += "(#{values.map(&:to_s).map(&:inspect).join(', ')})"
      end
      out_stream.puts s
    end
  end
end
