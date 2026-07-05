# frozen_string_literal: true

require 'shellwords'
require 'socket'
require 'tempfile'
require_relative 'helpers/resource_manager'
require_relative 'helpers/qr_code_generator'
require_relative '../errors'
require_relative '../runtime_config'
require_relative '../connectivity_states'
require_relative '../signal_quality'
require_relative '../string_predicates'
require_relative '../services/command_executor'
require_relative '../services/network_connectivity_tester'
require_relative '../services/network_state_manager'
require_relative '../services/status_waiter'
require_relative '../services/connection_manager'
require_relative '../services/disconnect_manager'
require_relative '../services/public_ip_lookup'
require_relative '../services/status_line_data_builder'
require_relative '../services/wifi_info_builder'
require_relative 'model_subclass_contract'
require_relative '../timing'

module WifiWand
  class BaseModel
    include StringPredicates
    include Timing

    Options = Struct.new(:verbose, :utc, :wifi_interface, :out_stream, :err_stream, keyword_init: true)

    # Shared normalization logic needed at both the class level (create_model)
    # and the instance level (initialize). Mixed in both ways below so each
    # call site can invoke it privately with an implicit receiver.
    module OptionsNormalization
      private def normalize_options(options)
        return Options.new(**options) if options.is_a?(Hash)
        return options if options.is_a?(Options)

        raise ArgumentError, 'options must be a Hash or WifiWand::BaseModel::Options'
      end
    end

    extend OptionsNormalization
    include OptionsNormalization

    attr_writer :wifi_interface
    attr_reader :runtime_config
    attr_accessor :command_executor, :connectivity_tester, :state_manager, :status_waiter,
      :connection_manager, :disconnect_manager

    def self.create_model(options = {})
      normalized_options = normalize_options(options)
      instance = new(normalized_options)
      # Eagerly validate an explicitly-specified interface; defer discovery otherwise.
      instance.init if normalized_options.wifi_interface
      instance
    end

    def self.current_os_matches_this_model?
      WifiWand::Platforms::Selector.current_os&.id == os_id
    end

    def self.inherited(subclass)
      super
      WifiWand::ModelSubclassContract.validate_subclass!(subclass)
    end

    def initialize(options = {})
      verify_subclass_contract

      options = normalize_options(options)
      @options = options
      # JRuby may bundle keyword-style arguments into a single positional Hash
      # when the caller itself accepts a positional options Hash. Build an
      # explicit Hash and splat it so keyword arguments are reliably delivered
      # to RuntimeConfig#initialize on all supported Ruby implementations.
      runtime_config_options = {
        verbose:    options[:verbose],
        utc:        options[:utc] || false,
        out_stream: options[:out_stream] || $stdout,
        err_stream: options[:err_stream] || $stderr,
      }
      @runtime_config = RuntimeConfig.new(**runtime_config_options)
      @command_executor = CommandExecutor.new(runtime_config: @runtime_config)
      @connectivity_tester = NetworkConnectivityTester.new(runtime_config: @runtime_config)
      @state_manager = NetworkStateManager.new(self, runtime_config: @runtime_config)
      @status_waiter = StatusWaiter.new(self, runtime_config: @runtime_config)
      @connection_manager = ConnectionManager.new(self, runtime_config: @runtime_config)
      @disconnect_manager = DisconnectManager.new(self, runtime_config: @runtime_config)
    end

    def out_stream = runtime_config.out_stream

    def out_stream=(stream)
      runtime_config.out_stream = stream
    end

    def err_stream = runtime_config.err_stream

    def err_stream=(stream)
      runtime_config.err_stream = stream
    end

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

    private def verify_subclass_contract
      return if instance_of?(BaseModel)

      WifiWand::ModelSubclassContract.verify_required_methods_implemented(self.class)
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

      wifi_info_builder.successful_available_network_scan(_available_network_names)
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

    # Returns true when WiFi is on and the interface is associated with an SSID.
    # Returns false when WiFi is off or there is no active SSID association.
    def associated?
      name = connected_network_name
      !name.nil? && !name.empty?
    rescue WifiWand::Error
      false
    end

    def disconnect
      debug_method_entry(__method__)
      @disconnect_manager.disconnect
    end

    def disconnect_stability_window_in_secs
      @disconnect_manager.disconnect_stability_window_in_secs
    end

    def disassociated_stable?
      @disconnect_manager.disassociated_stable?
    end

    def disconnect_associated?
      connected?
    end

    def connection_ready?(network_name)
      connected? && connected_network_name == network_name
    rescue WifiWand::MacOsRedactionError
      raise
    rescue WifiWand::Error => e
      err_stream.puts("connection_ready? check failed: #{e.class}: #{e.message}") if verbose?
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

    def run_command(command, raise_on_error: true, timeout_in_secs: nil, log_stdout: true,
      binary_stdout: false)
      @command_executor.run_command_using_args(command, raise_on_error: raise_on_error,
        timeout_in_secs: timeout_in_secs, log_stdout: log_stdout, binary_stdout: binary_stdout)
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

    # Returns comprehensive WiFi information including connectivity details
    def wifi_info
      debug_method_entry(__method__)
      wifi_info_builder.build
    end

    def wifi_info_builder
      @wifi_info_builder ||= WifiInfoBuilder.new(
        self, runtime_config: @runtime_config,
        expected_network_errors: NetworkErrorConstants::EXPECTED_NETWORK_ERRORS,
        network_operation_command_errors: NetworkErrorConstants::NETWORK_OPERATION_COMMAND_ERRORS
      )
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
        expected_network_errors: NetworkErrorConstants::EXPECTED_NETWORK_ERRORS
      )
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

    def public_ip_lookup = @public_ip_lookup ||= PublicIpLookup.new

    def public_ip_info = public_ip_lookup.info

    def public_ip_address = public_ip_lookup.address

    def public_ip_country = public_ip_lookup.country

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
    def resource_manager = @resource_manager ||= Models::Helpers::ResourceManager.new

    def open_resources_by_codes(*resource_codes)
      resource_manager.open_resources_by_codes(self, *resource_codes)
    end

    def available_resources_help = resource_manager.available_resources_help

    # QR code generator helper
    def qr_code_generator = @qr_code_generator ||= Models::Helpers::QrCodeGenerator.new

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

    # Generates a QR code for the currently connected WiFi network.
    # @param filespec [String, nil] Output path, or nil for the default generated PNG filename.
    # @return [String] The filename for file output.
    # @raise [WifiWand::Error] If not connected to a network or qrencode is not available
    def generate_qr_code(filespec = nil, overwrite: false, password: nil, in_stream: $stdin)
      debug_method_entry(__method__)
      qr_code_generator.generate(
        self, filespec, overwrite: overwrite, password: password, in_stream: in_stream
      )
    end

    # Renders a QR code for the currently connected WiFi network without writing or printing it.
    # @param format [Symbol] Output format to render. Supports :ansi, :png, :svg, and :eps.
    # @return [String] Rendered QR output.
    # @raise [WifiWand::Error] If not connected to a network or qrencode is not available
    def render_qr_code(format: :ansi, password: nil)
      debug_method_entry(__method__)
      qr_code_generator.render(self, format: format, password: password)
    end

    # Prints an ANSI QR code for the currently connected WiFi network.
    # @return [nil]
    # @raise [WifiWand::Error] If not connected to a network or qrencode is not available
    def print_qr_code(password: nil)
      debug_method_entry(__method__)
      out_stream.print(qr_code_generator.render(self, format: :ansi, password: password))
      nil
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
      err_stream.puts s
    end
  end
end
