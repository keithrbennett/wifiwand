require 'json'
require 'net/http'
require 'tempfile'
require 'uri'
require_relative 'helpers/command_output_formatter'
require_relative '../error'
require_relative '../../wifi-wand'

module WifiWand

class BaseModel

  attr_accessor :wifi_port, :verbose_mode

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


  def initialize(options)
    @verbose_mode = options.verbose

    if options.wifi_port && (! is_wifi_port?(options.wifi_port))
      raise Error.new("#{options.wifi_port} is not a Wi-Fi interface.")
    end
    @wifi_port = options.wifi_port
  end




  def run_os_command(command, raise_on_error = true)

    if @verbose_mode
      puts CommandOutputFormatter.command_attempt_as_string(command)
    end

    start_time = Time.now
    output = `#{command} 2>&1` # join stderr with stdout

    if @verbose_mode
      puts "Duration: #{'%.4f' % [Time.now - start_time]} seconds"
      puts CommandOutputFormatter.command_result_as_string(output)
    end

    if $?.exitstatus != 0 && raise_on_error
      raise OsCommandError.new($?.exitstatus, command, output)
    end

    output
  end


  # This method returns whether or not there is a working Internet connection,
  # which is defined as being able to get a successful response
  # from google.com within 3 seconds..
  def connected_to_internet?

    # We test using ping first because that will allow us to fail faster
    # if there is no network connection.
    test_using_ping = -> do
      run_os_command('ping -c 1 -t 3 google.com', false)
      $?.exitstatus == 0
    end


    test_using_http_get = -> do
      test_site = 'https://www.google.com'
      url = URI.parse(test_site)
      success = true

      if @verbose_mode
        puts CommandOutputFormatter.command_attempt_as_string("[Calling Net:HTTP.start(#{url.host})]")
      end

      start_time = Time.now

      begin
        Net::HTTP.start(url.host) do |http|
          http.read_timeout = 3 # seconds
          http.get('.')
        end
      rescue
        success = false
      end

      if @verbose_mode
        puts "Duration: #{'%.4f' % [Time.now - start_time]} seconds"
        puts CommandOutputFormatter.command_result_as_string("#{success}\n")
      end

      success
    end

    test_using_ping.() && test_using_http_get.()
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
  # @return names of the networks that were removed (excludes non-preexisting networks)
  def remove_preferred_networks(*network_names)
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
  # @return the stdout produced by the command
  def try_os_command_until(command, stop_condition, max_tries = 100)
    max_tries.times do
      stdout = run_os_command(command)
      if stop_condition.(stdout)
        return stdout
      end
    end
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


  def wifi_port
    @wifi_port ||= detect_wifi_port
  end
end
end