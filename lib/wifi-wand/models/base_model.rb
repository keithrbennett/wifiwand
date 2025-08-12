require 'json'
require 'net/http'
require 'tempfile'
require 'uri'
require_relative 'helpers/command_output_formatter'
require_relative '../error'

module WifiWand

class BaseModel

  attr_accessor :wifi_interface, :verbose_mode

  def initialize(options)
    @verbose_mode = options.verbose

    if options.wifi_interface
      if is_wifi_interface?(options.wifi_interface)
        @wifi_interface = options.wifi_interface
      else
        raise Error.new("#{options.wifi_interface} is not a Wi-Fi interface.")
      end
    else
      @wifi_interface = detect_wifi_interface
    end
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

  %i[
    available_network_names
    connected_network_name
    detect_wifi_interface
    disconnect
    ip_address
    is_wifi_interface?
    mac_address
    nameservers
    open_application
    open_resource
    os_level_connect
    os_level_preferred_network_password
    preferred_networks
    remove_preferred_network
    set_nameservers
    wifi_info
    wifi_off
    wifi_on
    wifi_on?
  ].each { |method_name| define_subclass_required_method(method_name) }

  def run_os_command(command, raise_on_error = true)
    if verbose_mode
      puts CommandOutputFormatter.command_attempt_as_string(command)
    end

    start_time = Time.now
    output = `#{command} 2>&1` # join stderr with stdout

    if verbose_mode
      puts "Duration: #{'%.4f' % [Time.now - start_time]} seconds"
      puts CommandOutputFormatter.command_result_as_string(output)
    end

    if $?.exitstatus != 0 && raise_on_error
      raise OsCommandError.new($?.exitstatus, command, output)
    end

    output
  end


  # This method returns whether or not there is a working Internet connection,
  # which is defined as success for both name resolution and an HTTP get.
  # Domains attempted are google.com and baidu.com.
  # Success is defined as either being successful.
  # Commands for the multiple sites are run in parallel, in threads, to save time.
  def connected_to_internet?
    return false unless wifi_on? # no need to try

    # We cannot use run_os_command for the running of external processes here,
    # because they are multithreaded, and the output will get mixed up.
    test_using_dig = -> do
      domains = %w(google.com  baidu.com)
      puts "Calling dig on domains #{domains}..." if verbose_mode

      threads = domains.map do |domain|
        Thread.new do
          output = `dig +short #{domain}`
          output.length > 0
        end
      end

      threads.each(&:join)
      values = threads.map(&:value)
      success = values.include?(true)
      puts "Results of dig: success == #{success}, values were #{values}." if verbose_mode
      success
    end

    test_using_http_get = -> do
      test_sites = %w{https://www.google.com  http://baidu.com}
      puts "Calling HTTP.get on sites #{test_sites}..." if verbose_mode

      threads = test_sites.map do |site|
        Thread.new do
          url = URI.parse(site)
          success = true
          start = Time.now

          begin
            Net::HTTP.start(url.host) do |http|
              http.read_timeout = 3 # seconds
              http.get('.')
              puts "Finished HTTP get #{url.host} in #{Time.now - start} seconds" if verbose_mode
            end
          rescue => e
            puts "Got error for host #{url.host} in #{Time.now - start} seconds:\n#{e.inspect}" if verbose_mode
            success = false
          end

          success
        end
      end

      threads.each(&:join)
      values = threads.map(&:value)
      success = values.include?(true)

      puts "Results of HTTP.get: success == #{success}, values were #{values}." if verbose_mode
      success
    end

    test_using_dig.() && test_using_http_get.()
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
  # Relies on subclass implementation of os_level_connect().
  def connect(network_name, password = nil)
    # Allow symbols and anything responding to to_s for user convenience
    network_name = network_name.to_s if network_name
    password     = password.to_s     if password

    if network_name.nil? || network_name.empty?
      raise Error.new("A network name is required but was not provided.")
    end
    wifi_on
    os_level_connect(network_name, password)

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
      raise Error.new(message)
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
    networks_to_remove.each { |name| remove_preferred_network(name) }
  end


  def preferred_network_password(preferred_network_name)
    preferred_network_name = preferred_network_name.to_s
    if preferred_networks.include?(preferred_network_name)
      os_level_preferred_network_password(preferred_network_name)
    else
      raise Error.new("Network #{preferred_network_name} not in preferred networks list.")
    end
  end


  # Waits for the Internet connection to be in the desired state.
  # @param target_status must be in [:conn, :disc, :off, :on]; waits for that state
  # @param wait_interval_in_secs sleeps this interval between retries; if nil or absent,
  #        a default will be provided
  #
  # Connected is defined as being able to connect to an external web site.
  def till(target_status, wait_interval_in_secs = nil)
    # One might ask, why not just put the 0.5 up there as the default argument.
    # We could do that, but we'd still need the line below in case nil
    # was explicitly specified. The default argument of nil above emphasizes that
    # the absence of an argument and a specification of nil will behave identically.
    wait_interval_in_secs ||= 0.5

    finished_predicates = {
        conn: -> { connected_to_internet? },
        disc: -> { ! connected_to_internet? },
        on:   -> { wifi_on? },
        off:  -> { ! wifi_on? }
    }

    finished_predicate = finished_predicates[target_status]

    if finished_predicate.nil?
      raise ArgumentError.new(
          "Option must be one of #{finished_predicates.keys.inspect}. Was: #{target_status.inspect}")
    end

    loop do
      return if finished_predicate.()
      sleep(wait_interval_in_secs)
    end
  end


  # Tries an OS command until the stop condition is true.
  # @command the command to run in the OS
  # @stop_condition a lambda taking the command's stdout as its sole parameter
  # @return the stdout produced by the command, or nil if max_tries was reached
  def try_os_command_until(command, stop_condition, max_tries = 100)

    report_attempt_count = ->(attempt_count) do
      puts "Command was executed #{attempt_count} time(s)." if verbose_mode
    end

    max_tries.times do |n|
      stdout_text = run_os_command(command)
      if stop_condition.(stdout_text)
        report_attempt_count.(n + 1)
        return stdout_text
      end
    end

    report_attempt_count.(max_tries)
    nil
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

  end

  class OsCommandError < RuntimeError
    attr_reader :exitstatus, :command, :text

    def initialize(exitstatus, command, text)
      @exitstatus = exitstatus
      @command = command
      @text = text
    end

    def to_s
      "#{self.class.name}: Error code #{exitstatus}, command = #{command}, text = #{text}"
    end

    def to_h
      { exitstatus: exitstatus, command: command, text: text }
    end
  end
end
