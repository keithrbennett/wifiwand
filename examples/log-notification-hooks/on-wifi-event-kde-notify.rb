#!/usr/bin/env ruby
# frozen_string_literal: true
#
# WiFi event hook: Send KDE Plasma system notifications
#
# Usage: wifi-wand log --hook ./on-wifi-event-kde-notify.rb
#
# Displays native KDE Plasma notifications for WiFi events.
# Only works on KDE Plasma; silently exits on other platforms.

require 'json'

event = JSON.parse($stdin.read)

# Only run on KDE Plasma (check for KDEDIR or KDE_FULL_SESSION)
kde_available = ENV['KDE_FULL_SESSION'] || ENV['KDEDIR'] ||
                system('which kdialog > /dev/null 2>&1')

exit 0 unless kde_available

begin
  Notification = Struct.new(:icon, :title, :message)

  fallback = Notification.new(
    'network-wireless',
    'WiFi Event',
    "Event: #{event['type']}"
  )

  notifications = {
    'wifi_on' => Notification.new(
      'network-wireless',
      'WiFi',
      'WiFi is now active'
    ),
    'wifi_off' => Notification.new(
      'network-wireless-off',
      'WiFi',
      'WiFi has been disabled'
    ),
    'connected' => Notification.new(
      'network-connect',
      'WiFi Connected',
      "Connected to: #{event.dig('details', 'network_name')}"
    ),
    'disconnected' => Notification.new(
      'network-disconnect',
      'WiFi Disconnected',
      "Disconnected from: #{event.dig('details', 'network_name')}"
    ),
    'internet_on' => Notification.new(
      'network-status-connected',
      'Internet',
      'Internet connection restored'
    ),
    'internet_off' => Notification.new(
      'network-status-offline',
      'Internet',
      'Internet connection lost'
    )
  }

  n = notifications.fetch(event['type'], fallback)

  # Send notification via kdialog (KDE Plasma)
  # kdialog uses: --passivepopup <text> [<timeout>] [--title <title>] [--icon <icon>]
  system(
    'kdialog',
    '--passivepopup', "#{n.title}\n#{n.message}",
    '5000',  # 5 second timeout
    '--title', 'wifi-wand',
    '--icon', n.icon,
    out: '/dev/null',
    err: '/dev/null'
  )
  exit Process.last_status.exitstatus

rescue StandardError => e
  warn "KDE notify hook error: #{e.message}"
  exit 1
end
