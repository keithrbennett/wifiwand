require 'json'
require 'net/http'
require 'socket'
require 'tempfile'
require 'uri'
require_relative 'helpers/command_output_formatter'
require_relative 'helpers/resource_manager'
require_relative '../errors'
require_relative '../services/command_executor'
require_relative '../services/network_connectivity_tester'
require_relative '../services/network_state_manager'
require_relative '../services/status_waiter'

module WifiWand

class BaseModel

  attr_accessor :wifi_interface, :verbose_mode, :command_executor, :connectivity_tester, :state_manager, :status_waiter

  def self.create_model(options = OpenStruct.new)
    instance = new(options)
    instance.init if current_os_matches_this_model?
    instance
  end

  def self.current_os_matches_this_model?
    WifiWand::OperatingSystems.current_os&.id == os_id
  end

  def initialize(options)
    @options = options
    @verbose_mode = options.verbose
    @command_executor = CommandExecutor.new(verbose: @verbose_mode)
    @connectivity_tester = NetworkConnectivityTester.new(verbose: @verbose_mode)
    @state_manager = NetworkStateManager.new(self, verbose: @verbose_mode)
    @status_waiter = StatusWaiter.new(self, verbose: @verbose_mode)
  end

  def init
    init_wifi_interface
    self
  end

  def init_wifi_interface
    validate_os_preconditions

    # Initialize wifi interface (e.g.: "wlp0s20f3")
    if @options.wifi_interface
      if is_wifi_interface?(@options.wifi_interface)
        @wifi_interface = @options.wifi_interface
      else
        raise InvalidInterfaceError.new(@options.wifi_interface)
      end
    else
      @wifi_interface = detect_wifi_interface
    end
    
    # Validate that wifi_interface is a valid string
    if @wifi_interface.nil? || @wifi_interface.empty?
      raise WifiInterfaceError.new
    end

    self
  end

  # @return array of nameserver IP addresses from /etc/resolv.conf, or nil if not found
  # This is the fallback method that works on most Unix-like systems
  def nameservers_using_resolv_conf
    begin
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end
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
  ].freeze

  # Verify that a subclass implements all required underscore-prefixed methods
  def self.verify_underscore_methods_implemented(subclass)
    missing_methods = UNDERSCORE_PREFIXED_METHODS - subclass.public_instance_methods
    unless missing_methods.empty?
      raise NotImplementedError, "Subclass #{subclass.name} must implement #{missing_methods.inspect}"
    end
  end

  # Automatically verify underscore methods when a subclass is inherited
  def self.inherited(subclass)
    trace = TracePoint.new(:end) do |tp|
      if tp.self == subclass
        verify_underscore_methods_implemented(subclass)
        trace.disable
      end
    end
    trace.enable
  end

  %i[
    default_interface
    detect_wifi_interface
    is_wifi_interface?
    mac_address
    nameservers
    open_application
    open_resource
    os_level_preferred_network_password
    preferred_networks
    remove_preferred_network
    set_nameservers
    validate_os_preconditions
    wifi_off
    wifi_on
    wifi_on?
  ].each { |method_name| define_subclass_required_method(method_name) }

  # Public wrapper methods with wifi_on? check
  def available_network_names
    wifi_on? ? _available_network_names : nil
  end

  def connected_network_name
    wifi_on? ? _connected_network_name : nil
  end

  def disconnect
    wifi_on? ? _disconnect : nil
  end

  def ip_address
    wifi_on? ? _ip_address : nil
  end

  def run_os_command(command, raise_on_error = true)
    @command_executor.run_os_command(command, raise_on_error)
  end


  # This method returns whether or not there is a working Internet connection.
  # Tests both TCP connectivity to internet hosts and DNS resolution.
  def connected_to_internet?
    return false unless wifi_on? # no need to try
    @connectivity_tester.connected_to_internet?
  end

  # Tests TCP connectivity to internet hosts (not localhost)
  def internet_tcp_connectivity?
    @connectivity_tester.tcp_connectivity?
  end

  # Tests DNS resolution capability
  def dns_working?
    @connectivity_tester.dns_working?
  end


  # Returns comprehensive WiFi information including connectivity details
  def wifi_info
    internet_tcp = begin
      internet_tcp_connectivity?
    rescue
      false
    end
    
    dns_working = begin
      dns_working?
    rescue
      false
    end
    
    connected = internet_tcp && dns_working

    info = {
        'wifi_on'                   => wifi_on?,
        'internet_tcp_connectivity' => internet_tcp,
        'dns_working'               => dns_working,
        'internet_on'               => connected,
        'interface'                 => wifi_interface,
        'default_interface'         => default_interface,
        'network'                   => connected_network_name,
        'ip_address'                => ip_address,
        'mac_address'               => mac_address,
        'nameservers'               => nameservers,
        'timestamp'                 => Time.now,
    }

    if info['internet_on']
      begin
        info['public_ip'] = public_ip_address_info
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, SocketError => e
        # Network connectivity issues - retry with exponential backoff
        begin
          sleep(0.5)
          info['public_ip'] = public_ip_address_info
        rescue => retry_error
          # Still failed - silently degrade (don't spam stdout)
          $stderr.puts "Warning: Could not obtain public IP info: #{retry_error.class}" if @verbose_mode
          info['public_ip'] = nil
        end
      rescue JSON::ParserError => e
        # Service returned invalid JSON - try alternate approach
        $stderr.puts "Warning: Public IP service returned invalid data" if @verbose_mode
        info['public_ip'] = nil  
      rescue => e
        # Other errors - log if verbose, gracefully degrade
        $stderr.puts "Warning: Public IP lookup failed: #{e.class}" if @verbose_mode
        info['public_ip'] = nil
      end
    end
    info
  end

  # Turns wifi off and then on, reconnecting to the originally connecting network.
  def cycle_network
    # TODO: Make this network name saving and restoring conditional on it not having a password.
    # If the disabled code below is enabled, an error will be raised if a password is required,
    # even though it is stored.
    # network_name = connected_network_name
    wifi_off
    wifi_on
    # connect(network_name) if network_name
  end


  def connected_to?(network_name)
    network_name == connected_network_name
  end


  # Connects to the passed network name, optionally with password.
  # Turns wifi on first, in case it was turned off.
  # Relies on subclass implementation of _connect().
  def connect(network_name, password = nil)
    # Allow symbols and anything responding to to_s for user convenience
    network_name = network_name&.to_s
    password     = password&.to_s

    if network_name.nil? || network_name.empty?
      raise InvalidNetworkNameError.new(network_name || "")
    end

    # If we're already connected to the desired network, no need to proceed
    return if network_name == connected_network_name

    wifi_on
    _connect(network_name, password)


    # Verify that the network is now connected:
    actual_network_name = connected_network_name

    unless actual_network_name == network_name
      message = %Q{Expected to connect to "#{network_name}" but }
      if actual_network_name.nil? || actual_network_name.empty?
        message << "unable to connect to any network."
      else
        message << %Q{connected to "#{connected_network_name}" instead.}
      end
      message << ' Did you ' << (password ? "provide the correct password?" : "need to provide a password?")
      raise NetworkConnectionError.new(network_name, actual_network_name ? "connected to '#{connected_network_name}' instead" : "unable to connect to any network")
    end
    nil
  end


  # Removes the specified network(s) from the preferred network list.
  # @param network_names names of networks to remove; may be empty or contain nonexistent networks
  #        can be a single arg which is an array of names or 1 name string per arg
  # @return names of the networks that were removed (excludes non-preexisting networks)
  def remove_preferred_networks(*network_names)
    network_names = network_names.first if network_names.first.is_a?(Array) && network_names.size == 1
    networks_to_remove = network_names & preferred_networks # exclude any nonexistent networks
    networks_to_remove.each { |name| remove_preferred_network(name.to_s) }
  end


  def preferred_network_password(preferred_network_name)
    preferred_network_name = preferred_network_name.to_s
    if preferred_networks.include?(preferred_network_name)
      os_level_preferred_network_password(preferred_network_name)
    else
      raise PreferredNetworkNotFoundError.new(preferred_network_name)
    end
  end


  # Waits for the Internet connection to be in the desired state.
  # @param target_status must be in [:conn, :disc, :off, :on]; waits for that state
  # @param wait_interval_in_secs sleeps this interval between retries; if nil or absent,
  #        a default will be provided
  #
  # Connected is defined as being able to connect to an external web site.
  def till(target_status, wait_interval_in_secs = nil)
    @status_waiter.wait_for(target_status, wait_interval_in_secs)
  end


  # Tries an OS command until the stop condition is true.
  # @command the command to run in the OS
  # @stop_condition a lambda taking the command's stdout as its sole parameter
  # @return the stdout produced by the command, or nil if max_tries was reached
  def try_os_command_until(command, stop_condition, max_tries = 100)
    @command_executor.try_os_command_until(command, stop_condition, max_tries)
  end


  # Reaches out to ipinfo.io to get public IP address information
  # in the form of a hash.
  # You may need to enclose this call in a begin/rescue.
  def public_ip_address_info
    JSON.parse(`curl -s ipinfo.io`)
  end


  def random_mac_address
    bytes = Array.new(6) { rand(256) }
    chars = bytes.map { |b| "%02x" % b }
    chars.join(':')
  end

  # Resource management functionality
  def resource_manager
    @resource_manager ||= Helpers::ResourceManager.new
  end

  def open_resources_by_codes(*resource_codes)
    resource_manager.open_resources_by_codes(self, *resource_codes)
  end

  def available_resources_help
    resource_manager.available_resources_help
  end

  # Network State Management for Testing
  # These methods help capture and restore network state during disruptive tests
  
  def capture_network_state
    @state_manager.capture_network_state
  end
  
  def restore_network_state(state, fail_silently: false)
    @state_manager.restore_network_state(state, fail_silently: fail_silently)
  end
  
  private

  def connected_network_password
    return nil unless connected_network_name
    preferred_network_password(connected_network_name)
  end

  def command_available_using_which?(command)
    @command_executor.command_available_using_which?(command)
  end

end
end
