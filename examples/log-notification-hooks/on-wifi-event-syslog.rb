#!/usr/bin/env ruby
# frozen_string_literal: true
#
# WiFi event hook: Send events to syslog
#
# Usage: wifi-wand log --hook ./on-wifi-event-syslog.rb
#
# Sends WiFi events to the system syslog with appropriate severity levels:
# - WiFi on/off: informational
# - Connected/disconnected: informational
# - Internet on/off: warning (off) / notice (on)

require 'json'
require 'syslog'

event = JSON.parse($stdin.read)

begin
  Syslog.open('wifi-wand', Syslog::LOG_PID, Syslog::LOG_USER) do |syslog|
    message = case event['type']
              when 'wifi_on'
                'WiFi turned on'
              when 'wifi_off'
                'WiFi turned off'
              when 'connected'
                network = event.dig('details', 'network_name')
                "Connected to network: #{network}"
              when 'disconnected'
                network = event.dig('details', 'network_name')
                "Disconnected from network: #{network}"
              when 'internet_on'
                'Internet connectivity restored'
              when 'internet_off'
                'Internet connectivity lost'
              else
                "WiFi event: #{event['type']}"
              end

    severity = case event['type']
               when 'internet_off'
                 Syslog::LOG_WARNING
               when 'internet_on'
                 Syslog::LOG_NOTICE
               else
                 Syslog::LOG_INFO
               end

    syslog.log(severity, message)
  end
rescue StandardError => e
  warn "Syslog hook error: #{e.message}"
  exit 1
end
