#!/usr/bin/env ruby
# frozen_string_literal: true
#
# WiFi event hook: Send macOS system notifications
#
# Usage: wifi-wand log --hook ./on-wifi-event-macos-notify.rb
#
# Displays native macOS notifications for WiFi events.
# Only works on macOS; silently exits on other platforms.

require 'json'

event = JSON.parse($stdin.read)

# Only run on macOS
exit 0 unless RUBY_PLATFORM.include?('darwin')

begin
  Notification = Struct.new(:title, :message)

  fallback = Notification.new(
    'WiFi Event',
    "Event: #{event['type']}"
  )

  notifications = {
    'wifi_on' => Notification.new(
      'WiFi Turned On',
      'WiFi is now active'
    ),
    'wifi_off' => Notification.new(
      'WiFi Turned Off',
      'WiFi has been disabled'
    ),
    'connected' => Notification.new(
      'WiFi Connected',
      "Connected to: #{event.dig('details', 'network_name')}"
    ),
    'disconnected' => Notification.new(
      'WiFi Disconnected',
      "Disconnected from: #{event.dig('details', 'network_name')}"
    ),
    'internet_on' => Notification.new(
      'Internet Available',
      'Internet connection restored'
    ),
    'internet_off' => Notification.new(
      'Internet Unavailable',
      'Internet connection lost'
    )
  }

  n = notifications.fetch(event['type'], fallback)

  # Send notification via terminal-notifier
  # Silently exit if terminal-notifier is not available
  exit 0 unless system('which terminal-notifier > /dev/null 2>&1')

  system('terminal-notifier', '-message', n.message, '-title', n.title)
  exit Process.last_status.exitstatus

rescue StandardError => e
  warn "macOS notify hook error: #{e.message}"
  exit 1
end
