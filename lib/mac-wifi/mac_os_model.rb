require 'shellwords'

require_relative 'base_model'

module MacWifi

class MacOsModel < BaseModel

  AIRPORT_CMD = '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

  def initialize(verbose = false)
    super
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
        'wifi_on'     =>    wifi_on?,
        'internet_on' => connected_to_internet?,
        'port'        => wifi_hardware_port,
        'network'     => current_network,
        'ip_address'  => ip_address,
        'nameservers' => nameservers_using_scutil,
        'timestamp'   => Time.now,
    }
    more_output = run_os_command(AIRPORT_CMD + " -I")
    more_info   = colon_output_to_hash(more_output)
    info.merge!(more_info)
    info.delete('AirPort') # will be here if off, but info is already in wifi_on key

    if info['wifi_on']
      begin
        info['public_ip'] = public_ip_address_info
      rescue => e
        puts "Error obtaining public IP address info, proceeding with everything else:"
        puts e.to_s
      end
    end
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
end