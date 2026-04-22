# frozen_string_literal: true

require 'rbconfig'
require 'open3'
require_relative '../wifi-wand/mac_helper/mac_os_wifi_auth_helper'
require_relative '../wifi-wand/mac_helper/mac_helper_release'

def ensure_os_is_mac
  unless RbConfig::CONFIG['host_os'] =~ /darwin/i
    abort 'This task is only supported on macOS.'
  end
end

namespace :mac do
  desc 'Print public macOS signing and notarization configuration'
  task :public_signing_info do
    ensure_os_is_mac

    helper = WifiWand::MacOsWifiAuthHelper
    profile_name = ENV.fetch(
      'WIFIWAND_NOTARYTOOL_PROFILE',
      WifiWand::MacHelperRelease::DEFAULT_NOTARYTOOL_PROFILE
    )
    keychain_path = ENV['WIFIWAND_NOTARYTOOL_KEYCHAIN']
    helper_exec_path = File.join(helper.source_bundle_path, 'Contents', 'MacOS', helper::EXECUTABLE_NAME)

    puts <<~INFO
      Public macOS signing and notarization info:
        Team ID: #{WifiWand::MacHelperRelease::APPLE_TEAM_ID}
        Codesign identity: #{WifiWand::MacHelperRelease::CODESIGN_IDENTITY}
        Notarytool profile: #{profile_name}
        Keychain path: #{keychain_path || '(login keychain default)'}
        Helper bundle path: #{helper.source_bundle_path}
        Helper executable path: #{helper_exec_path}
    INFO
  end

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
