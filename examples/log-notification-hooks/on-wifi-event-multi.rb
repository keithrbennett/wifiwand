#!/usr/bin/env ruby
# frozen_string_literal: true
#
# WiFi event hook: Compound hook that runs multiple hooks
#
# Usage: wifi-wand log --hook ./on-wifi-event-multi.rb
#
# This hook demonstrates how to orchestrate multiple hooks in a single
# command. It runs multiple hooks for each event, allowing you to combine:
# - System logging (syslog)
# - JSON logging (for analysis)
# - Desktop notifications (native to your environment)
# - Slack alerts (for important events)
#
# Configuration via environment variables:
#   WIFIWAND_MULTI_SYSLOG=true        # Enable syslog (default: true)
#   WIFIWAND_MULTI_JSON_LOG=true      # Enable JSON logging (default: true)
#   WIFIWAND_MULTI_NOTIFY=true        # Enable desktop notifications (default: true)
#   WIFIWAND_MULTI_SLACK=false        # Enable Slack (default: false - requires SLACK_WEBHOOK_URL)
#   WIFIWAND_MULTI_HOOK_DIR=.         # Directory containing hooks (default: current dir)
#
# Example:
#   export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
#   export WIFIWAND_MULTI_SLACK=true
#   wifi-wand log --hook ./on-wifi-event-multi.rb

require 'json'
require 'fileutils'

event_json = $stdin.read
event = JSON.parse(event_json)

# Configuration
hook_dir = ENV['WIFIWAND_MULTI_HOOK_DIR'] || '.'
enable_syslog = ENV.fetch('WIFIWAND_MULTI_SYSLOG', 'true') == 'true'
enable_json_log = ENV.fetch('WIFIWAND_MULTI_JSON_LOG', 'true') == 'true'
enable_notify = ENV.fetch('WIFIWAND_MULTI_NOTIFY', 'true') == 'true'
enable_slack = ENV.fetch('WIFIWAND_MULTI_SLACK', 'false') == 'true'

# Define which hooks to run
hooks_to_run = []

hooks_to_run << 'on-wifi-event-syslog.rb' if enable_syslog
hooks_to_run << 'on-wifi-event-json-log.rb' if enable_json_log

# For desktop notifications, detect which one to use
if enable_notify
  if RUBY_PLATFORM.include?('darwin')
    hooks_to_run << 'on-wifi-event-macos-notify.rb'
  elsif ENV['KDE_FULL_SESSION'] || ENV['KDEDIR'] ||
        system('which kdialog > /dev/null 2>&1', out: File::NULL, err: File::NULL)
    hooks_to_run << 'on-wifi-event-kde-notify.rb'
  elsif ENV['GNOME_DESKTOP_SESSION_ID'] || ENV['XDG_CURRENT_DESKTOP']&.include?('GNOME') ||
        system('which notify-send > /dev/null 2>&1', out: File::NULL, err: File::NULL)
    hooks_to_run << 'on-wifi-event-gnome-notify.rb'
  end
end

hooks_to_run << 'on-wifi-event-slack.rb' if enable_slack && ENV['SLACK_WEBHOOK_URL']

# Exit if no hooks are configured
if hooks_to_run.empty?
  warn 'No hooks configured to run'
  exit 1
end

# Run each hook
failed_hooks = []
hooks_to_run.each do |hook_name|
  hook_path = File.join(hook_dir, hook_name)

  unless File.exist?(hook_path)
    warn "Hook not found: #{hook_path}"
    failed_hooks << hook_name
    next
  end

  unless File.executable?(hook_path)
    warn "Hook not executable: #{hook_path}"
    failed_hooks << hook_name
    next
  end

  begin
    # Run hook with event JSON via stdin
    IO.popen([hook_path], 'w') do |io|
      io.write(event_json)
      io.close_write
    end

    # Check exit status
    unless Process.last_status.success?
      warn "Hook failed: #{hook_name} (exit code: #{Process.last_status.exitstatus})"
      failed_hooks << hook_name
    end
  rescue StandardError => e
    warn "Error running hook #{hook_name}: #{e.message}"
    failed_hooks << hook_name
  end
end

# Exit with error if any hooks failed
if failed_hooks.any?
  warn "#{failed_hooks.length} hook(s) failed: #{failed_hooks.join(', ')}"
  exit 1
end

exit 0
