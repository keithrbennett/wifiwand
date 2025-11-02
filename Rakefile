# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rbconfig'
require_relative 'lib/wifi-wand/mac_os_wifi_auth_helper'

namespace :swift do
  helper = WifiWand::MacOsWifiAuthHelper

  helper_source = helper.source_swift_path
  helper_binary = File.join(
    helper.source_bundle_path,
    'Contents',
    'MacOS',
    WifiWand::MacOsWifiAuthHelper::EXECUTABLE_NAME
  )

  file helper_binary => helper_source do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'macOS is required to compile Swift helpers.'
    end

    puts "Compiling #{helper_source} -> #{helper_binary}"
    helper.compile_helper(helper_source, helper_binary, out_stream: $stdout)
  end

  desc 'Compile the wifiwand macOS helper bundle executable'
  task :compile_helper => helper_binary

  desc 'Compile all Swift targets that require compilation'
  task :compile => [:compile_helper]
end

namespace :mac do
  desc 'Reset Location Services permission for wifiwand-helper via tccutil'
  task :reset_helper_location_permission do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'mac:reset_helper_location_permission is only supported on macOS hosts.'
    end

    bundle_id = 'com.wifiwand.helper'
    command = ['tccutil', 'reset', 'Location', bundle_id]

    puts command.join(' ')
    system(*command)
    status = Process.last_status

    unless status
      abort 'Failed to execute tccutil. Is it available on this system?'
    end

    case status.exitstatus
    when 0
      puts "Reset Location Services permission for #{bundle_id}."
    when 70
      puts "No stored Location Services decision found for #{bundle_id} (status 70)."
    else
      abort "tccutil reset failed with status #{status.exitstatus}. Check the output above for details."
    end
  end
end
