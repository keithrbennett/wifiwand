#!/usr/bin/env ruby
# frozen_string_literal: true

#
# WiFi event hook: Send notifications to Slack
#
# Usage: wifi-wand log --hook ./on-wifi-event-slack.rb
#
# Sends WiFi events to a Slack channel via incoming webhook.
#
# Setup:
#   1. Create a Slack app at https://api.slack.com/apps
#   2. Enable "Incoming Webhooks"
#   3. Create a webhook and copy the URL
#   4. Set environment variable:
#      export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
#   5. Run: wifi-wand log --hook ./on-wifi-event-slack.rb

require 'json'
require 'net/http'
require 'uri'

webhook_url = ENV.fetch('SLACK_WEBHOOK_URL', nil)

unless webhook_url
  warn 'Error: SLACK_WEBHOOK_URL environment variable not set'
  exit 1
end

event = JSON.parse($stdin.read)

begin
  # Determine message formatting based on event type
  case event['type']
  when 'wifi_on'
    color = 'good'
    title = ':wifi: WiFi Turned On'
  when 'wifi_off'
    color = 'danger'
    title = ':no_entry_sign: WiFi Turned Off'
  when 'connected'
    color = 'good'
    network = event.dig('details', 'network_name')
    title = ":link: Connected to #{network}"
  when 'disconnected'
    color = 'warning'
    network = event.dig('details', 'network_name')
    title = ":broken_link: Disconnected from #{network}"
  when 'internet_on'
    color = 'good'
    title = ':globe_with_meridians: Internet Available'
  when 'internet_off'
    color = 'danger'
    title = ':x: Internet Unavailable'
  else
    color = 'good'
    title = "WiFi Event: #{event['type']}"
  end

  # Build Slack message
  payload = {
    attachments: [
      {
        color: color,
        title: title,
        ts: Time.now.to_i
      }
    ]
  }

  # Send to Slack
  uri = URI(webhook_url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.open_timeout = 5
  http.read_timeout = 5

  request = Net::HTTP::Post.new(uri.path)
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(payload)

  response = http.request(request)
  exit 1 unless response.is_a?(Net::HTTPSuccess)
rescue => e
  warn "Slack hook error: #{e.message}"
  exit 1
end
