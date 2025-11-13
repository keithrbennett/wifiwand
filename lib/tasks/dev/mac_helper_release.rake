# frozen_string_literal: true

#
# Developer-only rake tasks for building, signing, and notarizing the macOS helper.
# These tasks are NOT included in the distributed gem.
#
# These tasks are run by the gem maintainer before releasing a new version.
# End users receive the pre-signed, pre-notarized helper binary.
#

require_relative '../../wifi-wand/mac_helper_release'

namespace :dev do
  desc 'Show quick reference for helper release tasks'
  task :help do
    puts <<~HELP
      wifi-wand macOS helper release tasks:

        Build & sign:
          op run --env-file=.env.release -- bundle exec rake dev:build_signed_helper

        Test:
          bundle exec rake dev:test_signed_helper

        Notarize:
          op run --env-file=.env.release -- bundle exec rake dev:notarize_helper

        Full workflow:
          op run --env-file=.env.release -- bundle exec rake dev:release_helper

        Notary queue tooling:
          op run --env-file=.env.release -- bundle exec rake dev:notarization_history
          op run --env-file=.env.release WIFIWAND_SUBMISSION_ID=<uuid> -- bundle exec rake dev:notarization_status
          op run --env-file=.env.release WIFIWAND_SUBMISSION_ID=<uuid> -- bundle exec rake dev:notarization_log
          op run --env-file=.env.release WIFIWAND_SUBMISSION_ID=<uuid> -- bundle exec rake dev:notarization_cancel

      See docs/dev/MACOS_CODE_SIGNING_INSTRUCTIONS.md for the checklist and
      docs/dev/MACOS_CODE_SIGNING_CONTEXT.md for the full background.
    HELP
  end

  desc 'Build and sign helper with Developer ID (for gem distribution)'
  task :build_signed_helper do
    puts 'Tip: run via bin/op-wrap bundle exec rake dev:build_signed_helper'
    WifiWand::MacHelperRelease.build_signed_helper
  end

  desc 'Test the signed helper binary'
  task :test_signed_helper do
    WifiWand::MacHelperRelease.test_signed_helper
  end

  desc 'Notarize the helper for distribution (requires Apple ID credentials)'
  task :notarize_helper do
    ensure_release_credentials!('dev:notarize_helper')
    puts 'Tip: run via bin/op-wrap bundle exec rake dev:notarize_helper'
    WifiWand::MacHelperRelease.notarize_helper
  end

  desc 'Complete release workflow: build, sign, test, notarize'
  task :release_helper do
    ensure_release_credentials!('dev:release_helper')
    WifiWand::MacHelperRelease.release_helper
  end

  desc 'Show code signing status of helper'
  task :codesign_status do
    WifiWand::MacHelperRelease.codesign_status
  end

  desc 'Show recent notarization submissions (uses Apple ID credentials)'
  task :notarization_history do
    ensure_release_credentials!('dev:notarization_history')
    WifiWand::MacHelperRelease.notarization_history
  end

  desc 'Show notarization status for a submission (pass WIFIWAND_SUBMISSION_ID=<uuid>)'
  task :notarization_status do
    ensure_release_credentials!('dev:notarization_status')
    WifiWand::MacHelperRelease.notarization_status(fetch_submission_id)
  end

  desc 'Show notarization log for a submission (pass WIFIWAND_SUBMISSION_ID=<uuid>)'
  task :notarization_log do
    ensure_release_credentials!('dev:notarization_log')
    WifiWand::MacHelperRelease.notarization_log(fetch_submission_id)
  end

  desc 'Cancel a notarization submission (defaults to oldest queued submission)'
  task :notarization_cancel do
    ensure_release_credentials!('dev:notarization_cancel')
    WifiWand::MacHelperRelease.cancel_notarization(
      fetch_submission_id(order: :asc, pending_only: true)
    )
  end
end

def fetch_submission_id(order: :desc, pending_only: false)
  submission_id = ENV['WIFIWAND_SUBMISSION_ID']
  submission_id = ENV['SUBMISSION_ID'] if submission_id.to_s.empty? # backward compatibility
  return submission_id unless submission_id.to_s.empty?

  normalized_order = WifiWand::MacHelperRelease.normalize_submission_order(order)
  auto_id = WifiWand::MacHelperRelease.select_submission_id(
    order: normalized_order,
    pending_only: pending_only
  )
  abort 'Error: Provide WIFIWAND_SUBMISSION_ID=<notarytool-submission-id>.' unless auto_id

  adjective = normalized_order == :asc ? 'oldest' : 'latest'
  puts "Info: No submission ID provided; using #{adjective} notary submission #{auto_id}."
  auto_id
end

def ensure_release_credentials!(task_name)
  return if ENV['WIFIWAND_DISABLE_AUTO_OP_RUN'] == '1'
  return if ENV['WIFIWAND_APPLE_DEV_ID'] && ENV['WIFIWAND_APPLE_DEV_PASSWORD']
  return if ENV['WIFIWAND_OP_RUN_ACTIVE'] == '1'

  wrapper = ENV['WIFIWAND_OP_WRAP_BIN'] || File.expand_path('../../bin/op-wrap', __dir__)
  wrapper_shell = ENV.fetch('WIFIWAND_OP_WRAP_SHELL', 'bash')

  unless File.exist?(wrapper)
    abort <<~ERROR
      Error: Unable to locate op wrapper at #{wrapper}.
      Ensure bin/op-wrap exists (or set WIFIWAND_OP_WRAP_BIN) and try again.

      To skip auto-wrapping entirely, set WIFIWAND_DISABLE_AUTO_OP_RUN=1.
    ERROR
  end

  puts "Re-running #{task_name} via #{File.basename(wrapper)}..."
  ENV['WIFIWAND_OP_RUN_ACTIVE'] = '1'
  exec(wrapper_shell, wrapper, 'bundle', 'exec', 'rake', task_name)
rescue SystemCallError => e
  abort "Error: unable to execute #{wrapper} for #{task_name}: #{e.message}"
end
