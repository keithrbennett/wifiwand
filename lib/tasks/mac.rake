# frozen_string_literal: true

require 'rbconfig'
require 'open3'
require_relative '../wifi-wand/mac_os_wifi_auth_helper'

def ensure_os_is_mac
  unless RbConfig::CONFIG['host_os'] =~ /darwin/i
    abort 'This task is only supported on macOS.'
  end
end

namespace :mac do
  desc 'Install development helper to user library (for testing)'
  task :install_dev_helper do
    ensure_os_is_mac

    helper = WifiWand::MacOsWifiAuthHelper
    source = helper.source_bundle_path
    dest = helper.installed_bundle_path

    unless File.exist?(source)
      abort "Source helper not found at #{source}. Run `bundle exec rake swift:compile` first."
    end

    puts 'Installing development helper...'
    puts "  From: #{source}"
    puts "  To:   #{dest}"

    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.rm_rf(dest)
    FileUtils.cp_r(source, dest)

    puts '✓ Development helper installed successfully'
  end

  desc 'Remove installed helper from user library'
  task :rm_helper do
    ensure_os_is_mac

    helper = WifiWand::MacOsWifiAuthHelper
    install_dir = File.dirname(helper.installed_bundle_path)

    if File.exist?(install_dir)
      puts "Removing helper installation at: #{install_dir}"
      FileUtils.rm_rf(install_dir)
      puts '✓ Helper removed successfully'
    else
      puts "Helper not present at #{install_dir}, no action necessary."
    end
  end
end
