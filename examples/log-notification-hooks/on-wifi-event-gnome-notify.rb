#!/usr/bin/env ruby
# frozen_string_literal: true
#
# WiFi event hook: Send GNOME system notifications
#
# Usage: wifi-wand log --hook ./on-wifi-event-gnome-notify.rb
#
# Displays native GNOME notifications for WiFi events via D-Bus.
# Works on GNOME and GNOME-based desktops (Ubuntu, Fedora, etc.).
# Silently exits on other platforms.

require 'json'

event = JSON.parse($stdin.read)

# Check if we're on GNOME (check for GNOME_DESKTOP_SESSION_ID or similar)
gnome_available = ENV['GNOME_DESKTOP_SESSION_ID'] || ENV['XDG_CURRENT_DESKTOP']&.include?('GNOME') ||
                  system('which notify-send > /dev/null 2>&1')

exit 0 unless gnome_available

begin
  Notification = Struct.new(:icon, :summary, :body)

  fallback = Notification.new(
    'network-wireless',
    'WiFi Event',
    "Event: #{event['type']}"
  )

  notifications = {
    'wifi_on' => Notification.new(
      'network-wireless',
      'WiFi Turned On',
      'WiFi is now active'
    ),
    'wifi_off' => Notification.new(
      'network-wireless-offline',
      'WiFi Turned Off',
      'WiFi has been disabled'
    ),
    'connected' => Notification.new(
      'network-wireless-connected',
      'Connected',
      "Connected to: #{event.dig('details', 'network_name')}"
    ),
    'disconnected' => Notification.new(
      'network-wireless-disconnected',
      'Disconnected',
      "Disconnected from: #{event.dig('details', 'network_name')}"
    ),
    'internet_on' => Notification.new(
      'network-ethernet-connected',
      'Internet Available',
      'Internet connection restored'
    ),
    'internet_off' => Notification.new(
      'network-ethernet-offline',
      'Internet Unavailable',
      'Internet connection lost'
    )
  }

  n = notifications.fetch(event['type'], fallback)

  # Send notification via notify-send (GNOME/freedesktop)
  # notify-send [OPTIONS] <SUMMARY> [BODY]
  system(
    'notify-send',
    '--app-name=wifi-wand',
    "--icon=#{n.icon}",
    '--expire-time=5000', # 5 seconds
    n.summary,
    n.body
  )
  exit Process.last_status.exitstatus

rescue StandardError => e
  warn "GNOME notify hook error: #{e.message}"
  exit 1
end
