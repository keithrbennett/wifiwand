require 'ipaddr'
require 'ostruct'
require 'rexml/document'
require 'shellwords'

require_relative 'base_model'
require_relative '../error'

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# 2024-04-18:
#
# Apple has deprecated the 'airport' utility and has already disabled its
# functionality. This utility is used for the following wifi-wand commands:

# 1) cmd: info, fn: wifi_info - adds information to the info output
# 2) cmd: avail_nets, fn: available_network_names - available wifi network names
# 3) cmd: ls_avail_nets, fn: available_network_info - available wifi networks details
# 4) cmd: wifi_on, fn: wifi_on?
# 5) cmd: network_name, fn: connected_network_name
# 6) cmd: disconnect, fn: disconnect

# Functions 4 and 5 have been fixed to use `networksetup` instead of `airport`.
# The others are not yet fixed.

# An AskDifferent (Mac StackExchange site) question has been posted to
# https://apple.stackexchange.com/questions/471886/how-to-replace-functionality-of-deprecated-airport-command-line-application.
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module WifiWand

class MacOsModel < BaseModel

  DEFAULT_AIRPORT_FILESPEC = '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

  attr_reader :airport_deprecated, :mac_os_version_major, :mac_os_version_minor, :mac_os_version_string

  # Takes an OpenStruct containing options such as verbose mode and interface name.
  def initialize(options = OpenStruct.new)
    super
    populate_mac_os_version
    @airport_deprecated = @mac_os_version_major > 14 || (@mac_os_version_major == 14 && @mac_os_version_minor >= 4)
  end

  # Provides Mac OS major and minor version numbers
  def populate_mac_os_version
    @mac_os_version_string = `sw_vers --productVersion`.chomp
    @mac_os_version_major, @mac_os_version_minor = mac_os_version_string.split('.').map(&:to_i)
    [@mac_os_version_major, @mac_os_version_minor]
  end

  def airport_deprecated_message
    <<~MESSAGE
      This method requires the airport utility which is no longer functional in Mac OS >= 14.4.
      You are running Mac OS version #{mac_os_version_string}.
    MESSAGE
  end

  # Although at this time the airport command utility is predictable,
  # allow putting it elsewhere in the path for overriding and easier fix
  # if that location should change.
  def airport_command
    airport_in_path = `which airport`.chomp
    if ! airport_in_path.empty?
      airport_in_path
    elsif File.exist?(DEFAULT_AIRPORT_FILESPEC)
      DEFAULT_AIRPORT_FILESPEC
    else
      raise Error.new("Airport command not found.")
    end
  end


  # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
  # This may not detect wifi ports with nonstandard names, such as USB wifi devices.
  def detect_wifi_interface

    lines = run_os_command("networksetup -listallhardwareports").split("\n")
    # Produces something like this:
    # Hardware Port: Wi-Fi
    # Device: en0
    # Ethernet Address: ac:bc:32:b9:a9:9d
    #
    # Hardware Port: Bluetooth PAN
    # Device: en3
    # Ethernet Address: ac:bc:32:b9:a9:9e

    wifi_interface_line_num = (0...lines.size).detect do |index|
      /: Wi-Fi$/.match(lines[index])
    end

    if wifi_interface_line_num.nil?
      raise Error.new(%Q{Wifi interface (e.g. "en0") not found in output of: networksetup -listallhardwareports})
    else
      lines[wifi_interface_line_num + 1].split(': ').last
    end
  end


  # Returns data pertaining to available wireless networks.
  # For some reason, this often returns no results, so I've put the operation in a loop.
  # I was unable to detect a sort strategy in the airport utility's output, so I sort
  # the lines alphabetically, to show duplicates and for easier lookup.
  #
  # Sample Output:
  #
  # => ["SSID                             BSSID             RSSI CHANNEL HT CC SECURITY (auth/unicast/group)",
  #     "ByCO-U00tRzUzMEg                 64:6c:b2:db:f3:0c -56  6       Y  -- NONE",
  #     "Chancery                         0a:18:d6:0b:b9:c3 -82  11      Y  -- NONE",
  #     "Chancery                         2a:a4:3c:03:33:99 -59  60,+1   Y  -- NONE",
  #     "DIRECT-sq-BRAVIA                 02:71:cc:87:4a:8c -76  6       Y  -- WPA2(PSK/AES/AES) ",  #
  def available_network_info

    if airport_deprecated
      warn airport_deprecated_message
      return nil
    end

    return nil unless wifi_on? # no need to try
    command = "#{airport_command} -s | iconv -f macroman -t utf-8"
    max_attempts = 50

    reformat_line = ->(line) do
      ssid = line[0..31].strip
      "%-32.32s%s" % [ssid, line[32..-1]]
    end

    signal_strength = ->(line) { (line[50..54] || '').to_i }

    sort_in_place_by_signal_strength = ->(lines) do
      lines.sort! { |x,y| signal_strength.(y) <=> signal_strength.(x) }
    end

    process_tabular_data = ->(output) do
      lines = output.split("\n")
      header_line = lines[0]
      data_lines = lines[1..-1]
      data_lines.map! do |line|
        # Reformat the line so that the name is left instead of right justified
        reformat_line.(line)
      end
      sort_in_place_by_signal_strength.(data_lines)
      [reformat_line.(header_line)] + data_lines
    end

    output = try_os_command_until(command, ->(output) do
      ! ([nil, ''].include?(output))
    end)

    if output
      process_tabular_data.(output)
    else
      raise Error.new("Unable to get available network information after #{max_attempts} attempts.")
    end
  end


  # The Mac OS airport utility (at
  # /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport)
  # outputs the network names right padded with spaces so there is no way to differentiate a
  # network name *with* leading space(s) from one without:
  #
  #                   SSID BSSID             RSSI CHANNEL HT CC SECURITY (auth/unicast/group)
  #    ngHub_319442NL0293C 04:a1:51:58:5b:05 -65  11      Y  US WPA2(PSK/AES/AES)
  #        NETGEAR89_2GEXT 9c:3d:cf:11:69:b4 -67  8       Y  US NONE
  #
  # To remedy this, they offer a "-x" option that outputs the information in (pseudo) XML.
  # This XML has 'dict' elements that contain many elements. The SSID can be found in the
  # XML element <string> which immediately follows an XML element whose text is "SSID_STR".
  # Unfortunately, since there is no way to connect the two other than their physical location,
  # the key is rather useless for XML parsing.
  #
  # I tried extracting the arrays of keys and strings, and finding the string element
  # at the same position in the string array as the 'SSID_STR' was in the keys array.
  # However, not all keys had string elements, so the index in the key array was the wrong index.
  # Here is an excerpt from the XML output:
  #
  # 		<key>RSSI</key>
  # 		<integer>-91</integer>
  # 		<key>SSID</key>
  # 		<data>
  # 		TkVUR0VBUjY1
  # 		</data>
  # 		<key>SSID_STR</key>
  # 		<string>NETGEAR65</string>
  #
  # The kludge I came up with was that the ssid was always the 2nd value in the <string> element
  # array, so that's what is used here.
  #
  # But now even that approach has been superseded by the XPath approach now used.
  #
  # REXML is used here to avoid the need for the user to install Nokogiri.
  def available_network_names
    if airport_deprecated
      warn airport_deprecated_message
      return nil
    end

    return nil unless wifi_on? # no need to try

    # For some reason, the airport command very often returns nothing, so we need to try until
    # we get data in the response:

    command = "#{airport_command} -s -x | iconv -f macroman -t utf-8"
    stop_condition = ->(response) { ! [nil, ''].include?(response) }
    output = try_os_command_until(command, stop_condition)
    doc = REXML::Document.new(output)
    xpath = '//key[text() = "SSID_STR"][1]/following-sibling::*[1]' # provided by @ScreenStaring on Twitter
    REXML::XPath.match(doc, xpath) \
        .map(&:text) \
        .sort { |x,y| x.casecmp(y) } \
        .uniq
  end


  # Returns data pertaining to "preferred" networks, many/most of which will probably not be available.
  def preferred_networks
    lines = run_os_command("networksetup -listpreferredwirelessnetworks #{wifi_interface}").split("\n")
    # Produces something like this, unsorted, and with leading tabs:
    # Preferred networks on en0:
    #         LibraryWiFi
    #         @thePAD/Magma

    lines.delete_at(0)                         # remove title line
    lines.map! { |line| line.gsub("\t", '') }  # remove leading tabs
    lines.sort! { |s1, s2| s1.casecmp(s2) }    # sort alphabetically, case insensitively
    lines
  end


  # Returns whether or not the specified interface is a WiFi interfae.
  def is_wifi_interface?(interface)
    run_os_command("networksetup -listpreferredwirelessnetworks #{interface} 2>/dev/null")
    exit_status = $?.exitstatus
    exit_status != 10
  end


  # Returns true if wifi is on, else false.
  def wifi_on?
    output = run_os_command("networksetup -getairportpower #{wifi_interface}")
    output.chomp.match?(/\): On$/)
  end


  # Turns wifi on.
  def wifi_on
    return if wifi_on?

    run_os_command("networksetup -setairportpower #{wifi_interface} on")
    wifi_on? ? nil : Error.new(raise("Wifi could not be enabled."))
  end


  # Turns wifi off.
  def wifi_off
    return unless wifi_on?

    run_os_command("networksetup -setairportpower #{wifi_interface} off")

    wifi_on? ? Error.new(raise("Wifi could not be disabled.")) : nil
  end


  # This method is called by BaseModel#connect to do the OS-specific connection logic.
  def os_level_connect(network_name, password = nil)
    command = "networksetup -setairportnetwork #{wifi_interface} " + "#{Shellwords.shellescape(network_name)}"
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


  # Returns the IP address assigned to the wifi interface, or nil if none.
  def ip_address
    return nil unless wifi_on? # no need to try
    begin
      run_os_command("ipconfig getifaddr #{wifi_interface}").chomp
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
                       "#{wifi_interface} #{Shellwords.shellescape(network_name)}")
  end


  # Returns the network currently connected to, or nil if none.
  def connected_network_name
    return nil unless wifi_on? # no need to try

    command_output = run_os_command("networksetup -getairportnetwork #{wifi_interface}")
    connected_prefix = 'Current Wi-Fi Network: '
    connected = Regexp.new(connected_prefix).match?(command_output)
    connected ? command_output.split(connected_prefix).last.chomp : nil
  end


  # Disconnects from the currently connected network. Does not turn off wifi.
  def disconnect
    if airport_deprecated
      warn airport_deprecated_message
      return nil
    end

    return nil unless wifi_on? # no need to try
    run_os_command("sudo #{airport_command} -z")
    nil
  end


  # TODO: Add capability to change the MAC address using a command in the form of:
  #     sudo ifconfig en0 ether aa:bb:cc:dd:ee:ff
  # However, the MAC address will be set to the real hardware address on restart.
  # One way to implement this is to have an optional address argument,
  # then this method returns the current address if none is provided,
  # but sets to the specified address if it is.
  def mac_address
    run_os_command("ifconfig #{wifi_interface} | awk '/ether/{print $2}'").chomp
  end


  # Returns some useful wifi-related information.
  def wifi_info

    connected = begin
      connected_to_internet?
    rescue
      false
    end

    need_hotspot_login = hotspot_login_required

    info = {
        'wifi_on'     => wifi_on?,
        'internet_on' => connected,
        'hotspot_login_required' => need_hotspot_login,
        'interface'   => wifi_interface,
        'network'     => connected_network_name,
        'ip_address'  => ip_address,
        'mac_address' => mac_address,
        'nameservers' => nameservers_using_scutil,
        'timestamp'   => Time.now,
    }

    unless airport_deprecated
      more_output = run_os_command(airport_command + " -I")
      more_info   = colon_output_to_hash(more_output)
      info.merge!(more_info)
      info.delete('AirPort') # will be here if off, but info is already in wifi_on key
    end

    if info['internet_on'] && (! need_hotspot_login)
      begin
        info['public_ip'] = public_ip_address_info
      rescue => e
        puts "Error obtaining public IP address info, proceeding with everything else:"
        puts e.to_s
      end
    end
    info
  end


  def set_nameservers(nameservers)
    arg = if nameservers == :clear
      'empty'
    else
      bad_addresses = nameservers.reject do |ns|
        begin
          IPAddr.new(ns).ipv4?
          true
        rescue => e
          puts e
          false
        end
      end

      unless bad_addresses.empty?
        raise Error.new("Bad IP addresses provided: #{bad_addresses.join(', ')}")
      end
      nameservers.join(' ')
    end # end assignment to arg variable

    run_os_command("networksetup -setdnsservers Wi-Fi #{arg}")
    nameservers
  end


  def open_application(application_name)
    run_os_command('open -a ' + application_name)
  end


  def open_resource(resource_url)
    run_os_command('open ' + resource_url)
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


  # @return array of nameserver IP addresses from /etc/resolv.conf, or nil if not found
  # Though this is strictly *not* OS-agnostic, it will be used by most OS's,
  # and can be overridden by subclasses (e.g. Windows).
  def nameservers_using_resolv_conf
    begin
      File.readlines('/etc/resolv.conf').grep(/^nameserver /).map { |line| line.split.last }
    rescue Errno::ENOENT
      nil
    end
  end


  def nameservers_using_scutil
    output = run_os_command('scutil --dns')
    nameserver_lines_scoped_and_unscoped = output.split("\n").grep(/^\s*nameserver\[/)
    unique_nameserver_lines = nameserver_lines_scoped_and_unscoped.uniq # take the union
    nameservers = unique_nameserver_lines.map { |line| line.split(' : ').last.strip }
    nameservers
  end


  def nameservers_using_networksetup
    output = run_os_command("networksetup -getdnsservers Wi-Fi")
    if output == "There aren't any DNS Servers set on Wi-Fi.\n"
      output = ''
    end
    output.split("\n")
  end
end
end
