require 'ipaddr'
require 'ostruct'
require 'shellwords'

require_relative 'base_model'
require_relative '../error'

module WifiWand

class MacOsModel < BaseModel

  # Takes an OpenStruct containing options such as verbose mode and interface name.
  def initialize(options = OpenStruct.new)
    super
  end

  # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
  # This may not detect wifi ports with nonstandard names, such as USB wifi devices.
  def detect_wifi_interface_using_networksetup

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

  # Identifies the (first) wireless network hardware interface in the system, e.g. en0 or en1
  # This may not detect wifi ports with nonstandard names, such as USB wifi devices.
  def detect_wifi_interface
    json_text = run_os_command('system_profiler -json SPNetworkDataType')
    net_data = JSON.parse(json_text)
    nets = net_data['SPNetworkDataType']
    
    return nil if nets.nil? || nets.empty?
    
    wifi = nets.detect { |net| net['_name'] == 'Wi-Fi'}
    
    if wifi.nil?
      raise Error.new(%Q{Wi-Fi interface not found in output of: system_profiler -json SPNetworkDataType})
    end
    
    interface = wifi['interface']
    if interface.nil? || interface.empty?
      raise Error.new(%Q{Wi-Fi interface name not found in network data for Wi-Fi service})
    end
    
    interface
  end

  # Returns the network names sorted in descending order of signal strength.
  def _available_network_names

    json_text = run_os_command('system_profiler -json SPAirPortDataType')
    data = JSON.parse(json_text)

    inner_key = connected_network_name ? 'spairport_airport_other_local_wireless_networks' : 'spairport_airport_local_wireless_networks'

    nets = data['SPAirPortDataType'] \
       .detect { |h| h.key?('spairport_airport_interfaces') } \
        ['spairport_airport_interfaces'] \
       .detect { |h| h['_name'] == wifi_interface } \
        [inner_key] \
        .sort_by { |net| -net['spairport_signal_noise'].split('/').first.to_i }
    nets.map { |h| h['_name']}.uniq
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


  # Returns whether or not the specified interface is a WiFi interface.
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
  def os_level_connect_using_networksetup(network_name, password = nil)
    command = "networksetup -setairportnetwork #{wifi_interface} #{Shellwords.shellescape(network_name)}"
    if password
      command << ' ' << Shellwords.shellescape(password)
    end
    run_os_command(command)
  end

  def os_level_connect_using_swift(network_name, password = nil)
    ensure_swift_and_corewlan_present
    args = [Shellwords.shellescape(network_name)]
    args << Shellwords.shellescape(password) if password
    run_swift_command('WifiNetworkConnector', *args)
  end

  def _connect(network_name, password = nil)
    os_level_connect_using_swift(network_name, password)
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
  def _ip_address
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
  def _connected_network_name

    command_output = run_os_command("ipconfig getsummary #{wifi_interface} | grep ' SSID :'", false)
    return nil if command_output.empty?

    command_output.split('SSID :').last.strip
  end


  # Disconnects from the currently connected network. Does not turn off wifi.
  def _disconnect

    run_swift_command('WifiNetworkDisconnector')
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

  def nameservers
    # Use scutil for the most accurate DNS information on Mac OS
    nameservers_using_scutil
  end

  def ensure_swift_and_corewlan_present
    unless swift_and_corewlan_present?
      raise RuntimeError, <<~MESSAGE
        Swift and/or CoreWLAN are not present and are needed by this task.
        This can be fixed by installing XCode.
      MESSAGE
    end
  end

  def swift_and_corewlan_present?
    system("swift -e 'import CoreWLAN' >/dev/null 2>&1")
  end


  def run_swift_command(basename, *args)
    ensure_swift_and_corewlan_present
    swift_filespec = File.absolute_path(File.join(File.dirname(__FILE__), "../../../swift/#{basename}.swift"))
    argv = ['swift', swift_filespec] + args
    command = argv.compact.join(' ')
    run_os_command(command)
  end
end
end
