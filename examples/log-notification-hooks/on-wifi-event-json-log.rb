#!/usr/bin/env ruby
# frozen_string_literal: true

#
# WiFi event hook: Log events as JSON to a file
#
# Usage: wifi-wand log --hook ./on-wifi-event-json-log.rb
#
# Logs WiFi events as newline-delimited JSON (NDJSON) for easy parsing and analysis.
# Default location: ~/.local/share/wifi-wand/event-log.jsonl
#
# Environment variables:
#   WIFIWAND_JSON_LOG_FILE - Custom log file path (default shown above)

require 'json'
require 'fileutils'

event = JSON.parse($stdin.read)

default_dir = File.expand_path('~/.local/share/wifi-wand')
log_file = ENV['WIFIWAND_JSON_LOG_FILE'] ||
           File.join(default_dir, 'event-log.jsonl')

begin
  # Ensure default directory exists (only auto-create for default location)
  FileUtils.mkdir_p(default_dir) unless ENV['WIFIWAND_JSON_LOG_FILE']

  # Append event as JSON line
  File.open(log_file, 'a') { |f| f.puts(JSON.generate(event)) }
rescue => e
  warn "JSON log hook error: #{e.message}"
  exit 1
end
