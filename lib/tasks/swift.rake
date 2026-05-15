# frozen_string_literal: true

require 'rbconfig'
require_relative '../wifi_wand/platforms/mac/helper/bundle'
require_relative '../wifi_wand/platforms/mac/helper/build'

namespace :swift do
  helper = WifiWand::Platforms::Mac::Helper::Bundle
  helper_binary = helper.source_bundle_executable_path

  desc 'Compile the wifiwand macOS helper bundle executable (supports optional WIFIWAND_CODESIGN_IDENTITY)'
  task :compile_helper do
    source_bundle_current = begin
      File.exist?(helper_binary) && helper.source_bundle_current?
    rescue Errno::ENOENT
      false
    end
    rebuild_needed = !source_bundle_current

    if rebuild_needed
      unless RbConfig::CONFIG['host_os'] =~ /darwin/i
        abort 'macOS is required to compile Swift helpers.'
      end

      helper.build_source_bundle(out_stream: $stdout)
      helper.verify_source_bundle_current!
    end
  end

  desc 'Verify the committed wifiwand macOS helper bundle matches the current source attestation inputs'
  task :verify_helper_attestation do
    helper.verify_source_bundle_current!
    puts 'Source attestation matches committed helper source, entitlements, and bundle contents.'
  end

  desc 'Verify the committed wifiwand macOS helper bundle code signature'
  task :verify_helper_signature do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'macOS is required to verify the shipped helper code signature.'
    end

    helper.verify_source_bundle_signature!
    puts 'Code signature verifies for committed helper bundle.'
  end

  desc 'Verify the committed wifiwand macOS helper bundle attestation and code signature'
  task verify_helper: %i[verify_helper_attestation verify_helper_signature]

  desc 'Compile all Swift targets that require compilation (supports optional WIFIWAND_CODESIGN_IDENTITY)'
  task compile: [:compile_helper]
end
