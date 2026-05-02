# frozen_string_literal: true

require 'rbconfig'
require_relative '../wifi-wand/mac_helper/mac_os_helper_bundle'
require_relative '../wifi-wand/mac_helper/mac_os_helper_build'

namespace :swift do
  helper = WifiWand::MacOsHelperBundle

  helper_binary = helper.source_bundle_executable_path

  file helper_binary => helper.build_task_prerequisites do
    unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      abort 'macOS is required to compile Swift helpers.'
    end

    puts "Compiling #{helper.source_swift_path} -> #{helper_binary}"
    helper.build_source_bundle(out_stream: $stdout)
  end

  desc 'Compile the wifiwand macOS helper bundle executable (requires WIFIWAND_CODESIGN_IDENTITY)'
  task :compile_helper do
    source_bundle_stale = !File.exist?(helper_binary) || !helper.source_bundle_current?

    Rake::Task[helper_binary].execute if source_bundle_stale
    helper.verify_source_bundle_current!
  end

  desc 'Verify the committed wifiwand macOS helper bundle matches the current source attestation inputs'
  task :verify_helper do
    helper.verify_source_bundle_current!
    puts 'Source attestation matches committed helper source, entitlements, and bundle contents.'
  end

  desc 'Compile all Swift targets that require compilation (requires WIFIWAND_CODESIGN_IDENTITY)'
  task compile: [:compile_helper]
end
