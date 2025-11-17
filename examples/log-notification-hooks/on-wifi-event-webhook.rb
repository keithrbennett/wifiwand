#!/usr/bin/env ruby
# frozen_string_literal: true

#
# WiFi event hook: Send events via HTTP webhook
#
# Usage: wifi-wand log --hook ./on-wifi-event-webhook.rb
#
# Posts WiFi events to any HTTP endpoint as JSON.
#
# Setup:
#   1. Determine your webhook URL (e.g., monitoring service, custom endpoint)
#   2. Set environment variable:
#      export WEBHOOK_URL="https://your-service.com/wifi-events"
#   3. Run: wifi-wand log --hook ./on-wifi-event-webhook.rb
#
# The full event JSON is sent as the POST body.

require 'json'
require 'net/http'
require 'uri'

webhook_url = ENV.fetch('WEBHOOK_URL', nil)

unless webhook_url
  warn 'Error: WEBHOOK_URL environment variable not set'
  exit 1
end

event = JSON.parse($stdin.read)

begin
  uri = URI(webhook_url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.open_timeout = 5
  http.read_timeout = 5

  request = Net::HTTP::Post.new(uri.request_uri)
  request['Content-Type'] = 'application/json'
  request['User-Agent'] = 'wifi-wand/1.0'
  request.body = JSON.generate(event)

  response = http.request(request)

  # Retry once on transient failure
  if !response.is_a?(Net::HTTPSuccess) && response.is_a?(Net::HTTPServerError)
    sleep 1
    response = http.request(request)
  end

  exit 1 unless response.is_a?(Net::HTTPSuccess)
rescue => e
  warn "Webhook hook error: #{e.message}"
  exit 1
end
