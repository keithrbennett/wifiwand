# frozen_string_literal: true

require 'rbconfig'
require_relative '../wifi_wand/platforms/mac/helper/bundle'
require_relative '../wifi_wand/platforms/mac/helper/build'
require_relative '../wifi_wand/platforms/mac/helper/git_skip_worktree'
require_relative '../wifi_wand/platforms/mac/helper/release'

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
    WifiWand::Platforms::Mac::Helper::Release.verify_source_attestation!
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

  # These tasks manage a local Git index flag, not repository content. The macOS
  # helper app contains tracked generated artifacts because releases ship a
  # signed, prebuilt bundle, but frequent local helper rebuilds can otherwise be
  # swept into unrelated commits by `git add .`. `swift:helper_skip:start` hides
  # only the generated executable, signing metadata, and manifest from normal
  # staging; it leaves the Swift source and helper bundle template files visible.
  # `swift:helper_skip:stop` must be used before release work so the regenerated
  # helper artifact is visible to Git and can be staged intentionally.
  namespace :helper_skip do
    desc 'Start skip-worktree for generated macOS helper artifact files'
    task :start do
      WifiWand::Platforms::Mac::Helper::GitSkipWorktree.new.start
    end

    desc 'Stop skip-worktree for generated macOS helper artifact files'
    task :stop do
      WifiWand::Platforms::Mac::Helper::GitSkipWorktree.new.stop
    end

    desc 'Show skip-worktree status for generated macOS helper artifact files'
    task :status do
      WifiWand::Platforms::Mac::Helper::GitSkipWorktree.new.print_status
    end
  end
end
