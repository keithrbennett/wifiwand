# frozen_string_literal: true

require 'rbconfig'
require 'open3'
require_relative '../wifi-wand/mac_os_wifi_auth_helper'

AUTH_VALUE_LABELS = {
  0 => 'Denied',
  1 => 'Restricted',
  2 => 'Allowed',
  3 => 'Limited',
  4 => 'Unknown (4)'
}.freeze

def format_location_auth_value(value)
  AUTH_VALUE_LABELS.fetch(value.to_i, "Unknown (#{value})")
end

def tcc_database_path
  File.expand_path('~/Library/Application Support/com.apple.TCC/TCC.db')
end

def reset_helper_location_permission_internal
  bundle_id = 'com.wifiwand.helper'
  command = ['tccutil', 'reset', 'Location', bundle_id]

  puts command.join(' ')
  stdout, stderr, status = Open3.capture3(*command)

  unless status
    abort 'Failed to execute tccutil. Is it available on this system?'
  end

  # Print any output from the command (stderr to stdout to maintain order)
  puts stdout unless stdout.empty?
  puts stderr unless stderr.empty?

  exit_code = status.exitstatus
  case exit_code
  when 0
    puts "Reset Location Services permission for #{bundle_id}."
  when 64
    puts "No TCC entry found for bundle identifier #{bundle_id} (status 64)."
  when 70
    puts "No stored Location Services decision found for #{bundle_id} (status 70)."
  when 77
    puts 'tccutil could not modify permissions (status 77). This usually happens inside a sandboxed environment.'
    puts 'Re-run the task outside the sandbox or from the host shell with the necessary privileges.'
  else
    abort "tccutil reset failed with status #{exit_code}. Check the output above for details."
  end
end

def prompt_for_helper_location_permission(desired_action)
  helper = WifiWand::MacOsWifiAuthHelper
  helper.ensure_helper_installed(out_stream: $stdout)
  executable = helper.installed_executable_path

  unless File.exist?(executable)
    abort "Helper executable not found at #{executable}. Run `bundle exec rake swift:compile` first."
  end

  action_text = desired_action == 'allow' ? 'Allow' : "Don't Allow"
  puts 'Triggering Location Services prompt via wifiwand-helper.'
  puts "When the prompt appears, choose '#{action_text}'."
  puts 'If no prompt appears, the permission may already be set.'

  system(executable, '--command', 'current-network')
  puts 'Helper finished. Run `rake mac:helper_location_permission_status` to verify the recorded permission.'
end

namespace :mac do
  desc 'Show Location Services permission status for wifiwand-helper'
  task :helper_location_permission_status do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'mac:helper_location_permission_status is only supported on macOS hosts.'
    end

    db_path = tcc_database_path
    unless File.exist?(db_path)
      puts 'No TCC database found for the current user. No Location Services decisions have been recorded yet.'
      next
    end

    helper = WifiWand::MacOsWifiAuthHelper
    bundle_id = 'com.wifiwand.helper'
    executable_path = helper.installed_executable_path

    conditions = [
      "client = '#{bundle_id}'",
      "client LIKE '%wifiwand-helper%'"
    ]
    if File.exist?(executable_path)
      sanitized_exec = executable_path.gsub("'", "''")
      conditions << "client = '#{sanitized_exec}'"
    end

    query = <<~SQL
      SELECT client, client_type, auth_value,
             datetime(last_modified, 'unixepoch') AS modified
      FROM access
      WHERE service = 'kTCCServiceLocation'
        AND (#{conditions.join(' OR ')})
      ORDER BY last_modified DESC;
    SQL

    stdout, stderr, status = Open3.capture3('sqlite3', db_path, '-separator', '|', query)

    if status.exitstatus != 0
      warn "sqlite3 error: #{stderr.strip.empty? ? 'unknown error' : stderr.strip}"
      next
    end

    lines = stdout.lines.map(&:strip).reject(&:empty?)
    if lines.empty?
      puts 'No Location Services entry found for wifiwand-helper.'
      next
    end

    puts 'Location Services entries for wifiwand-helper:'
    lines.each do |line|
      client, client_type, auth_value, modified = line.split('|')
      type_label = client_type == '0' ? 'bundle identifier' : 'executable path'
      puts "- #{format_location_auth_value(auth_value)} (auth=#{auth_value}) for #{client} [#{type_label}] at #{modified}"
    end
  end

  desc 'Reset Location Services permission for wifiwand-helper'
  task :helper_location_permission_reset do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'mac:helper_location_permission_reset is only supported on macOS hosts.'
    end

    reset_helper_location_permission_internal
  end

  desc 'Set Location Services permission to "Allow" for wifiwand-helper'
  task :helper_location_permission_allow do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'mac:helper_location_permission_allow is only supported on macOS hosts.'
    end

    reset_helper_location_permission_internal
    prompt_for_helper_location_permission('allow')
  end

  desc 'Set Location Services permission to "Deny" for wifiwand-helper'
  task :helper_location_permission_deny do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'mac:helper_location_permission_deny is only supported on macOS hosts.'
    end

    reset_helper_location_permission_internal
    prompt_for_helper_location_permission('deny')
  end
end
