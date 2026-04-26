#!/usr/bin/env ruby
# frozen_string_literal: true

#
# examples/basic_usage.rb
#
# This script demonstrates basic usage of the wifi-wand gem as a library.
# To run this script, make sure you have the gem installed (`gem install wifi-wand`).
# Then, you can execute it with `ruby examples/basic_usage.rb`.

require 'wifi-wand'

puts 'WifiWand Library - Basic Usage Example'
puts '---------------------------------------'

begin
  # 1. Create the OS-specific model for the current host.
  # This will automatically detect your operating system (macOS or Ubuntu).
  model = WifiWand.create_model

  # 2. Check the current Wi-Fi status.
  if model.wifi_on?
    puts '✅ Wi-Fi is ON.'
    puts "   - Connected to: #{model.connected_network_name || 'None'}"
    puts "   - IP Address:   #{model.ip_address || 'N/A'}"
  else
    puts '❌ Wi-Fi is OFF.'
  end

  # 3. List available Wi-Fi networks.
  puts "\n🔎 Scanning for available networks..."
  networks = model.available_network_names

  if networks&.any?
    puts "   Found #{networks.count} networks (in descending order of signal strength):\n\n"
    networks.each { |ssid| puts "     - #{ssid}" }
  else
    puts '   No networks found. Ensure your Wi-Fi is enabled.'
  end

  # 4. Get detailed information.
  # The `wifi_info` method returns a comprehensive hash of network details.
  puts "\nℹ️  Fetching detailed Wi-Fi info..."
  info = model.wifi_info
  puts "   - Default Interface: #{info['default_interface']}"
  puts "   - Internet Connected?: #{info['internet_on']}"
rescue WifiWand::NoSupportedOSError
  puts "\nError: This system is not a supported operating system (macOS or Ubuntu)."
rescue => e
  puts "\nAn unexpected error occurred: #{e.message}"
end
