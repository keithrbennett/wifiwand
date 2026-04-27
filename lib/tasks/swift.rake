# frozen_string_literal: true

require 'rbconfig'
require_relative '../wifi-wand/mac_helper/mac_os_wifi_auth_helper'
require_relative '../wifi-wand/mac_helper/mac_os_helper_build'

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
    helper.write_source_bundle_manifest
  end

  desc 'Compile the wifiwand macOS helper bundle executable (requires WIFIWAND_CODESIGN_IDENTITY)'
  task compile_helper: helper_binary

  desc 'Verify the committed wifiwand macOS helper bundle matches the current Swift source'
  task :verify_helper do
    helper.verify_source_bundle_current!
    puts 'Source attestation matches committed Swift source and bundle.'
  end

  desc 'Compile all Swift targets that require compilation (requires WIFIWAND_CODESIGN_IDENTITY)'
  task compile: [:compile_helper]
end
