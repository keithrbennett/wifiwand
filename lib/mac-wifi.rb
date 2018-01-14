#!/usr/bin/env ruby

# This script brings together several useful wifi-related functions.
#
# It is a bit of a kludge in that it calls Mac OS commands and uses
# the text output for its data. At some point I would like to replace
# that with system calls. Currently this script can break if Apple
# decides to modify the name, options, behavior, and/or format of its utilities.
#
# What would be *really* nice, would be for Apple to retrofit all
# system commands to optionally output JSON and/or YAML. Some offer XML, but that
# is not convenient to use.
#
# Mac OS commands currently used are: airport, ipconfig, networksetup, security.
#
# Author: keithrbennett (on Github, GMail, Twitter)
# I am available for Ruby development, troubleshooting, training, tutoring, etc.
#
# License: MIT License


require 'json'
require 'yaml'

require 'shellwords'
require 'tempfile'

module MacWifi

# This version must be kept in sync with the version in the gemspec file.
VERSION = '2.0.0'


class BaseModel

  class OsCommandError < RuntimeError
    attr_reader :exitstatus, :command, :text

    def initialize(exitstatus, command, text)
      @exitstatus = exitstatus
      @command = command
      @text = text
    end
  end


  def initialize(verbose = false)
    @verbose_mode = verbose
  end


  def run_os_command(command)
    output = `#{command} 2>&1` # join stderr with stdout
    if $?.exitstatus != 0
      raise OsCommandError.new($?.exitstatus, command, output)
    end
    if @verbose_mode
      puts "\n\n#{'-' * 79}\nCommand: #{command}\n\nOutput:\n#{output}#{'-' * 79}\n\n"
    end
    output
  end
  private :run_os_command


  # This method returns whether or not there is a working Internet connection.
  # Because of a Mac issue which causes a request to hang if the network is turned
  # off during its lifetime, we give it only 5 seconds per try,
  # and limit the number of tries to 3.
  #
  # This implementation will probably strike you as overly complex. The following
  # code looks like it is all that should be necessary, but unfortunately
  # this implementation often hangs when wifi is turned off while curl is active
  #
  # def connected_to_internet?
  #   script = "curl --silent --head http://www.google.com/ > /dev/null ; echo $?"
  #   result = `#{script}`.chomp
  #   puts result
  #   result == '0'
  # end

  # TODO Investigate using Curl options: --connect-timeout 1 --max-time 2 --retry 0
  # to greatly simplify this method.
  def connected_to_internet?

    tempfile = Tempfile.open('mac-wifi-')

    begin
      start_status_script = -> do
        script = "curl --silent --head http://www.google.com/ > /dev/null ; echo $? > #{tempfile.path} &"
        pid = Process.spawn(script)
        Process.detach(pid)
        pid
      end

      process_is_running = ->(pid) do
        script = %Q{ps -p #{pid} > /dev/null; echo $?}
        output = `#{script}`.chomp
        output == "0"
      end

      get_connected_state_from_curl = -> do
        tempfile.close
        File.read(tempfile.path).chomp == '0'
      end

      # Do one run, iterating during the timeout period to see if the command has completed
      do_one_run = -> do
        end_time = Time.now + 3
        pid = start_status_script.()
        while Time.now < end_time
          if process_is_running.(pid)
            sleep 0.5
          else
            return get_connected_state_from_curl.()
          end
        end
        Process.kill('KILL', pid) if process_is_running.(pid)
        :hung
      end

      3.times do
        connected = do_one_run.()
        return connected if connected != :hung
      end

      raise "Could not determine Internet status."

    ensure
      tempfile.unlink
    end

  end


  # Turns wifi off and then on, reconnecting to the originally connecting network.
  def cycle_network
    # TODO: Make this network name saving and restoring conditional on it not having a password.
    # If the disabled code below is enabled, an error will be raised if a password is required,
    # even though it is stored.
    # network_name = current_network
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
      raise "A network name is required but was not provided."
    end
    wifi_on
    os_level_connect(network_name, password)

    # Verify that the network is now connected:
    actual_network_name = connected_network_name
    unless actual_network_name == network_name
      message = %Q{Expected to connect to "#{network_name}" but }
      if actual_network_name
        message << %Q{connected to "#{connected_network_name}" instead.}
      else
        message << "unable to connect to any network. Did you "
      end
      message << (password ? "provide the correct password?" : "need to provide a password?")
      raise message
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
      raise "Network #{preferred_network_name} not in preferred networks list."
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
  # @stop_condition a lambda taking the commands stdout as its sole parameter
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
end


class MacOsModel < BaseModel

  AIRPORT_CMD = '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

  def initialize(verbose = false)
    super
  end


  # This is determined by whether or not a line like the following appears in the output of `netstat -nr`:
  # 0/1                10.137.0.41        UGSc           15        0   utun1
  def vpn_running?
    run_os_command('netstat -nr').split("\n").grep(/^0\/1.*utun1/).any?
  end


  # Identifies the (first) wireless network hardware port in the system, e.g. en0 or en1
  def wifi_hardware_port
    @wifi_hardware_port ||= begin
      lines = run_os_command("networksetup -listallhardwareports").split("\n")
      # Produces something like this:
      # Hardware Port: Wi-Fi
      # Device: en0
      # Ethernet Address: ac:bc:32:b9:a9:9d
      #
      # Hardware Port: Bluetooth PAN
      # Device: en3
      # Ethernet Address: ac:bc:32:b9:a9:9e
      wifi_port_line_num = (0...lines.size).detect do |index|
        /: Wi-Fi$/.match(lines[index])
      end
      if wifi_port_line_num.nil?
        raise %Q{Wifi port (e.g. "en0") not found in output of: networksetup -listallhardwareports}
      else
        lines[wifi_port_line_num + 1].split(': ').last
      end
    end
  end


  # Returns data pertaining to available wireless networks.
  # For some reason, this often returns no results, so I've put the operation in a loop.
  # I was unable to detect a sort strategy in the airport utility's output, so I sort
  # the lines alphabetically, to show duplicates and for easier lookup.
  def available_network_info
    return nil unless wifi_on? # no need to try
    command = "#{AIRPORT_CMD} -s"
    max_attempts = 50


    reformat_line = ->(line) do
      ssid = line[0..31].strip
      "%-32.32s%s" % [ssid, line[32..-1]]
    end


    process_tabular_data = ->(output) do
      lines = output.split("\n")
      header_line = lines[0]
      data_lines = lines[1..-1]
      data_lines.map! do |line|
        # Reformat the line so that the name is left instead of right justified
        reformat_line.(line)
      end
      data_lines.sort!
      [reformat_line.(header_line)] + data_lines
    end


    output = try_os_command_until(command, ->(output) do
      ! ([nil, ''].include?(output))
    end)

    if output
      process_tabular_data.(output)
    else
      raise "Unable to get available network information after #{max_attempts} attempts."
    end
  end


  def parse_network_names(info)
    if info.nil?
      nil
    else
      info[1..-1] \
        .map { |line| line[0..32].rstrip } \
        .uniq \
        .sort { |s1, s2| s1.casecmp(s2) }
    end
  end

  # @return an array of unique available network names only, sorted alphabetically
  # Kludge alert: the tabular data does not differentiate between strings with and without leading whitespace
  # Therefore, we get the data once in tabular format, and another time in XML format.
  # The XML element will include any leading whitespace. However, it includes all <string> elements,
  # many of which are not network names.
  # As an improved approximation of the correct result, for each network name found in tabular mode,
  # we look to see if there is a corresponding string element with leading whitespace, and, if so,
  # replace it.
  #
  # This will not behave correctly if a given name has occurrences with different amounts of whitespace,
  # e.g. ' x' and '     x'.
  #
  # The reason we don't use an XML parser to get the exactly correct result is that we don't want
  # users to need to install any external dependencies in order to run this script.
  def available_network_names

    # Parses the XML text (using grep, not XML parsing) to find
    # <string> elements, and extracts the network name candidates
    # containing leading spaces from it.
    get_leading_space_names = ->(text) do
      text.split("\n") \
          .grep(%r{<string>}) \
          .sort \
          .uniq \
          .map { |line| line.gsub("<string>", '').gsub('</string>', '').gsub("\t", '') } \
          .select { |s| s[0] == ' ' }
    end


    output_is_valid = ->(output) { ! ([nil, ''].include?(output)) }
    tabular_data = try_os_command_until("#{AIRPORT_CMD} -s", output_is_valid)
    xml_data     = try_os_command_until("#{AIRPORT_CMD} -s -x", output_is_valid)

    if tabular_data.nil? || xml_data.nil?
      raise "Unable to get available network information; please try again."
    end

    tabular_data_lines = tabular_data[1..-1] # omit header line
    names_no_spaces    = parse_network_names(tabular_data_lines.split("\n")).map(&:strip)
    names_maybe_spaces =  get_leading_space_names.(xml_data)

    names = names_no_spaces.map do |name_no_spaces|
      match = names_maybe_spaces.detect do |name_maybe_spaces|
        %r{[ \t]?#{name_no_spaces}$}.match(name_maybe_spaces)
      end

      match ? match : name_no_spaces
    end

    names.sort { |s1, s2| s1.casecmp(s2) }    # sort alphabetically, case insensitively
  end


  # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
  def preferred_networks
    lines = run_os_command("networksetup -listpreferredwirelessnetworks #{wifi_hardware_port}").split("\n")
    # Produces something like this, unsorted, and with leading tabs:
    # Preferred networks on en0:
    #         LibraryWiFi
    #         @thePAD/Magma

    lines.delete_at(0)                         # remove title line
    lines.map! { |line| line.gsub("\t", '') }  # remove leading tabs
    lines.sort! { |s1, s2| s1.casecmp(s2) }    # sort alphabetically, case insensitively
    lines
  end


  # Returns true if wifi is on, else false.
  def wifi_on?
    lines = run_os_command("#{AIRPORT_CMD} -I").split("\n")
    lines.grep("AirPort: Off").none?
  end


  # Turns wifi on.
  def wifi_on
    return if wifi_on?
    run_os_command("networksetup -setairportpower #{wifi_hardware_port} on")
    wifi_on? ? nil : raise("Wifi could not be enabled.")
  end


  # Turns wifi off.
  def wifi_off
    return unless wifi_on?
    run_os_command("networksetup -setairportpower #{wifi_hardware_port} off")
    wifi_on? ? raise("Wifi could not be disabled.") : nil
  end


  def connected_network_name
    wifi_info['SSID']
  end


  # This method is called by BaseModel#connect to do the OS-specific connection logic.
  def os_level_connect(network_name, password = nil)
    command = "networksetup -setairportnetwork #{wifi_hardware_port} " + "#{Shellwords.shellescape(network_name)}"
    if password
      command << ' ' << Shellwords.shellescape(password)
    end
    run_os_command(command)
  end


  # @return:
  #   If the network is in the preferred networks list
  #     If a password is associated w/this network, return the password
  #     If not, return nil
  #   else
  #     raise an error
  def os_level_preferred_network_password(preferred_network_name)
    command = %Q{security find-generic-password -D "AirPort network password" -a "#{preferred_network_name}" -w 2>&1}
    begin
      return run_os_command(command).chomp
    rescue OsCommandError => error
      if error.exitstatus == 44 # network has no password stored
        nil
      else
        raise
      end
    end
  end


  # Returns the IP address assigned to the wifi port, or nil if none.
  def ip_address
    begin
      run_os_command("ipconfig getifaddr #{wifi_hardware_port}").chomp
    rescue OsCommandError => error
      if error.exitstatus == 1
        nil
      else
        raise
      end
    end
  end


  def remove_preferred_network(network_name)
    network_name = network_name.to_s
    run_os_command("sudo networksetup -removepreferredwirelessnetwork " +
        "#{wifi_hardware_port} #{Shellwords.shellescape(network_name)}")
  end


  # Returns the network currently connected to, or nil if none.
  def current_network
    lines = run_os_command("#{AIRPORT_CMD} -I").split("\n")
    ssid_lines = lines.grep(/ SSID:/)
    ssid_lines.empty? ? nil : ssid_lines.first.split('SSID: ').last.strip
  end


  # Disconnects from the currently connected network. Does not turn off wifi.
  def disconnect
    run_os_command("sudo #{AIRPORT_CMD} -z")
    nil
  end


  # Returns some useful wifi-related information.
  def wifi_info

    info = {
        wifi_on:     wifi_on?,
        internet_on: connected_to_internet?,
        vpn_on:      vpn_running?,
        port:        wifi_hardware_port,
        network:     current_network,
        ip_address:  ip_address,
        timestamp:   Time.now,
    }
    more_output = run_os_command(AIRPORT_CMD + " -I")
    more_info   = colon_output_to_hash(more_output)
    info.merge!(more_info)
    info.delete('AirPort') # will be here if off, but info is already in wifi_on key
    info
  end


  # Parses output like the text below into a hash:
  # SSID: Pattara211
  # MCS: 5
  # channel: 7
  def colon_output_to_hash(output)
    lines = output.split("\n")
    lines.each_with_object({}) do |line, new_hash|
      key, value = line.split(': ')
      key = key.strip
      value.strip! if value
      new_hash[key] = value
    end
  end
  private :colon_output_to_hash
end


class CommandLineInterface

  attr_reader :model, :interactive_mode, :options

  class Command < Struct.new(:min_string, :max_string, :action); end


  class BadCommandError < RuntimeError
    def initialize(error_message)
      super
    end
  end


  # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
  HELP_TEXT = "
Command Line Switches:                    [mac-wifi version #{VERSION}]

-o[i,j,p,y]               - outputs data in inspect, JSON, puts, or YAML format when not in shell mode
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:

a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
cy[cle]                   - turns wifi off, then on, preserving network selection
d[isconnect]              - disconnects from current network, does not turn off wifi
h[elp]                    - prints this help
i[nfo]                    - a hash of wifi-related information
l[s_avail_nets]           - details about available networks
n[etwork_name]            - name (SSID) of currently connected network
on                        - turns wifi on
of[f]                     - turns wifi off
pa[ssword] network-name   - password for preferred network-name
pr[ef_nets]               - preferred (not necessarily available) networks
q[uit]                    - exits this program (interactive shell mode only) (see also 'x')
r[m_pref_nets] network-name - removes network-name from the preferred networks list
                            (can provide multiple names separated by spaces)
s[hell]                   - opens an interactive pry shell (command line only)
t[ill]                    - returns when the desired Internet connection state is true. Options:
                            1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                            2) wait interval, in seconds (optional, defaults to 0.5 seconds)
w[ifion]                  - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
    * use quotes for string parameters such as method names.
    * for pry commands, use prefix `%`.

"


  def initialize(options)
    @options = options
    @model = MacOsModel.new(verbose_mode)
    @interactive_mode = !!(options.interactive_mode)
    run_shell if @interactive_mode
  end


  # Until command line option parsing is added, the only way to specify
  # verbose mode is in the environment variable MAC_WIFI_OPTS.
  def verbose_mode
    options.verbose
  end


  def print_help
    puts HELP_TEXT
  end


  # @return true if awesome_print is available (after requiring it), else false after requiring 'pp'.
  # We'd like to use awesome_print if it is available, but not require it.
  # So, we try to require it, but if that fails, we fall back to using pp (pretty print),
  # which is included in Ruby distributions without the need to install a gem.
  def awesome_print_available?
    if @awesome_print_available.nil?  # first time here
      begin
        require 'awesome_print'
        @awesome_print_available = true
      rescue LoadError
        require 'pp'
        @awesome_print_available = false
      end
    end

    @awesome_print_available
  end


  def fancy_string(object)
    awesome_print_available? ? object.ai : object.pretty_inspect
  end


  def fancy_puts(object)
    puts fancy_string(object)
  end
  alias_method :fp, :fancy_puts


  def puts_unless_interactive(string)
    puts(string) unless interactive_mode
  end


  # Asserts that a command has been passed on the command line.
  def validate_command_line
    if ARGV.empty?
      puts "Syntax is: #{__FILE__} [options] command [command_options]"
      print_help
      exit(-1)
    end
  end


  # Pry will output the content of the method from which it was called.
  # This small method exists solely to reduce the amount of pry's output
  # that is not needed here.
  def run_pry
    binding.pry

    # the seemingly useless line below is needed to avoid pry's exiting
    # (see https://github.com/deivid-rodriguez/pry-byebug/issues/45)
    _a = nil
  end


  # Runs a pry session in the context of this object.
  # Commands and options specified on the command line can also be specified in the shell.
  def run_shell
    begin
      require 'pry'
    rescue LoadError
      puts "The 'pry' gem and/or one of its prerequisites, required for running the shell, was not found." +
               " Please `gem install pry`."
      exit(-1)
    end

    print_help

    # Enable the line below if you have any problems with pry configuration being loaded
    # that is messing up this runtime use of pry:
    # Pry.config.should_load_rc = false

    # Strangely, this is the only thing I have found that successfully suppresses the
    # code context output, which is not useful here. Anyway, this will differentiate
    # a pry command from a DSL command, which _is_ useful here.
    Pry.config.command_prefix = '%'

    run_pry
  end


  # For use by the shell; when typing a command and options, it is passed to process_command_line
  def method_missing(method_name, *options)
    method_name = method_name.to_s
    method_exists = !! find_command_action(method_name)
    if method_exists
      process_command_line(method_name, options)
    else
      puts(%Q{"#{method_name}" is not a valid command or option. If you intend for this to be a string literal, use quotes or %q/Q{}.})
    end
  end


  # Processes the command (ARGV[0]) and any relevant options (ARGV[1..-1]).
  #
  # CAUTION! In interactive mode, any strings entered (e.g. a network name) MUST
  # be in a form that the Ruby interpreter will recognize as a string,
  # i.e. single or double quotes, %q, %Q, etc.
  # Otherwise it will assume it's a method name and pass it to method_missing!
  def process_command_line(command, options)
    action = find_command_action(command)
    if action
      action.(*options)
    else
      print_help
      raise BadCommandError.new(
          %Q{Unrecognized command. Command was "#{command}" and options were #{options.inspect}.})
    end
  end


  def quit
    if interactive_mode
      exit(0)
    else
      puts "This command can only be run in shell mode."
    end
  end


  def cmd_a
    info = model.available_network_names
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        message = if model.wifi_on?
          "Available networks are:\n\n#{fancy_string(info)}"
        else
          "Wifi is off, cannot see available networks."
        end
        puts(message)
      end
    end
  end


  def cmd_ci
    connected = model.connected_to_internet?
    if interactive_mode
      connected
    else
      puts (post_processor ? post_processor.(connected) : "Connected to Internet: #{connected}")
    end
  end


  def cmd_co(network, password = nil)
    model.connect(network, password)
  end


  def cmd_cy
    model.cycle_network
  end


  def cmd_d
    model.disconnect
  end


  def cmd_h
    print_help
  end


  def cmd_i
    info = model.wifi_info
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        puts fancy_string(info)
      end
    end
  end


  def cmd_lsa
    info = model.available_network_info
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        message = model.wifi_on? ? fancy_string(info) : "Wifi is off, cannot see available networks."
        puts(message)
      end
    end
  end


  def cmd_n
    name = model.connected_network_name
    if interactive_mode
      name
    else
      display_name = name ? name : '[none]'
      puts (post_processor ? post_processor.(name) : %Q{Network (SSID) name: "#{display_name}"})
    end
  end


  def cmd_of
    model.wifi_off
  end


  def cmd_on
    model.wifi_on
  end


  def cmd_pa(network)
    password = model.preferred_network_password(network)

    if interactive_mode
      password
    else
      if post_processor
        puts post_processor.(password)
        else
          output =  %Q{Preferred network "#{model.connected_network_name}" }
          output << (password ? %Q{stored password is "#{password}".} : "has no stored password.")
          puts output
      end
    end
  end


  def cmd_pr
    networks = model.preferred_networks
    if interactive_mode
      networks
    else
      puts (post_processor ? post_processor.(networks) : fancy_string(networks))
    end
  end


  def cmd_q
    quit
  end


  def cmd_r(*options)
    removed_networks = model.remove_preferred_networks(*options)
    if interactive_mode
      removed_networks
    else
      puts (post_processor ? post_processor.(removed_networks) : "Removed networks: #{removed_networks.inspect}")
    end
  end


  def cmd_t(*options)
    target_status = options[0].to_sym
    wait_interval_in_secs = (options[1] ? Float(options[1]) : nil)
    model.till(target_status, wait_interval_in_secs)
  end


  def cmd_w
    on = model.wifi_on?
    if interactive_mode
      on
    else
      puts (post_processor ? post_processor.(on) : "Wifi on: #{on}")
    end
  end


  def cmd_x
    quit
  end


  def commands
    @commands_ ||= [
        Command.new('a',   'avail_nets',    -> (*_options) { cmd_a             }),
        Command.new('ci',  'ci',            -> (*_options) { cmd_ci            }),
        Command.new('co',  'connect',       -> (*options)  { cmd_co(*options)  }),
        Command.new('cy',  'cycle',         -> (*_options) { cmd_cy            }),
        Command.new('d',   'disconnect',    -> (*_options) { cmd_d             }),
        Command.new('h',   'help',          -> (*_options) { cmd_h             }),
        Command.new('i',   'info',          -> (*_options) { cmd_i             }),
        Command.new('l',   'ls_avail_nets', -> (*_options) { cmd_lsa           }),
        Command.new('n',   'network_name',  -> (*_options) { cmd_n             }),
        Command.new('of',  'off',           -> (*_options) { cmd_of            }),
        Command.new('on',  'on',            -> (*_options) { cmd_on            }),
        Command.new('pa',  'password',      -> (*options)  { cmd_pa(*options)  }),
        Command.new('pr',  'pref_nets',     -> (*_options) { cmd_pr            }),
        Command.new('q',   'quit',          -> (*_options) { cmd_q             }),
        Command.new('r',   'rm_pref_nets',  -> (*options)  { cmd_r(*options)   }),
        Command.new('t',   'till',          -> (*options)  { cmd_t(*options)   }),
        Command.new('w',   'wifion',        -> (*_options) { cmd_w             }),
        Command.new('x',   'xit',           -> (*_options) { cmd_x             })
    ]
  end


  def find_command_action(command_string)
    result = commands.detect do |cmd|
        cmd.max_string.start_with?(command_string) \
        && \
        command_string.length >= cmd.min_string.length  # e.g. 'c' by itself should not work
    end

    result ? result.action : nil
  end


  # If a post-processor has been configured (e.g. YAML or JSON), use it.
  def post_process(object)
    post_processor ? post_processor.(object) : object
  end



  def post_processor
    options.post_processor
  end


  def call
    validate_command_line
    begin
      process_command_line(ARGV[0], ARGV[1..-1])
    rescue BadCommandError => error
      separator_line = "! #{'-' * 75} !\n"
      puts '' << separator_line << error.to_s << "\n" << separator_line
      exit(-1)
    end
  end
end


require 'optparse'
require 'ostruct'

class Main

  # @return true if this file is being run as a script, else false
  #
  # This file could be called as a script in either of these two ways:
  #
  # 1) by loading this file directly, or
  # 2) by running as a gem executable's binstub, in (relatively) '../../../exe'
  #
  # For example, I get this when running this file as a gem and running:
  #
  # puts "$0: #{$0}"
  # puts "__FILE__: #{__FILE__}"
  # puts "GEM_PATH: #{ENV['GEM_PATH']}"
  #
  # $0: /Users/kbennett/.rvm/gems/ruby-2.4.1/bin/mac-wifi
  # __FILE__: /Users/kbennett/.rvm/gems/ruby-2.4.1/gems/mac-wifi-1.2.0/exe/mac-wifi
  # GEM_PATH: /Users/kbennett/.rvm/gems/ruby-2.4.1:/Users/kbennett/.rvm/gems/ruby-2.4.1@global


  def running_as_script?

    this_source_file = File.expand_path(__FILE__)
    called_file      = File.expand_path($0)
    return true if called_file == this_source_file

    this_source_file_basename = File.basename(this_source_file)
    called_file_basename      = File.basename(called_file)
    return false if called_file_basename != this_source_file_basename

    # If here, then filespecs are different but have the same basename.
    gem_roots = ENV['GEM_PATH'].split(File::PATH_SEPARATOR)
    as_script = gem_roots.any? do |gem_root|
      binstub_candidate_name = File.join(gem_root, 'bin', called_file_basename)
      up_4_from_this_source_file = File.expand_path(File.join(this_source_file, '..', '..', '..', '..'))
      found = ($0 == binstub_candidate_name) && (gem_root == up_4_from_this_source_file)
      found
    end

    as_script
  end


  def assert_os_is_mac_os
    host_os = RbConfig::CONFIG["host_os"]
    unless /darwin/.match(host_os)  # e.g. "darwin16.4.0"
      raise "This program currently works only on Mac OS. Platform is '#{host_os}'."
    end
  end


  # Parses the command line with Ruby's internal 'optparse'.
  # Looks for "-v" flag to set verbosity to true.
  # optparse removes what it processes from ARGV, which simplifies our command parsing.
  def parse_command_line
    options = OpenStruct.new
    OptionParser.new do |parser|
      parser.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      parser.on("-s", "--shell", "Start interactive shell") do |v|
        options.interactive_mode = true
      end

      parser.on("-o", "--output_format FORMAT", "Format output data") do |v|

        transformers = {
            'i' => ->(object) { object.inspect },
            'j' => ->(object) { JSON.pretty_generate(object) },
            'p' => ->(object) { sio = StringIO.new; sio.puts(object); sio.string },
            'y' => ->(object) { object.to_yaml }
        }

        choice = v[0].downcase

        unless transformers.keys.include?(choice)
          raise %Q{Output format "#{choice}" not in list of available formats} +
              " (#{transformers.keys.inspect})."
        end

        options.post_processor = transformers[choice]
      end

      parser.on("-h", "--help", "Show help") do |_help_requested|
        ARGV << 'h' # pass on the request to the command processor
      end
    end.parse!
    options
  end


  def call
    assert_os_is_mac_os

    options = parse_command_line

    # If this file is being called as a script, run it.
    # Else, it may be loaded to use the model in a different way.
    if running_as_script?
      begin
        MacWifi::CommandLineInterface.new(options).call
      end
    end
  end
end


end # module MacWifi


MacWifi::Main.new.call