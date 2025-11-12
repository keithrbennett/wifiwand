# frozen_string_literal: true

require 'rbconfig'
require_relative '../wifi-wand/mac_os_wifi_auth_helper'

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

  desc 'Compile the wifiwand macOS helper bundle as universal binary for arm64+x86_64 (requires WIFIWAND_CODESIGN_IDENTITY)'
  task :compile_helper => helper_binary

  desc 'Compile all Swift targets that require compilation as universal binaries (requires WIFIWAND_CODESIGN_IDENTITY)'
  task :compile => [:compile_helper]
end
