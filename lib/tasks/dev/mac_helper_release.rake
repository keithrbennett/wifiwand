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
          op run --env-file=.env.release SUBMISSION_ID=<uuid> -- bundle exec rake dev:notarization_status
          op run --env-file=.env.release SUBMISSION_ID=<uuid> -- bundle exec rake dev:notarization_log

      See docs/dev/MACOS_CODE_SIGNING_INSTRUCTIONS.md for the checklist and
      docs/dev/MACOS_CODE_SIGNING_CONTEXT.md for the full background.
    HELP
  end

  desc 'Build and sign helper with Developer ID (for gem distribution)'
  task :build_signed_helper do
    puts 'Tip: run via op run --env-file=.env.release -- bundle exec rake dev:build_signed_helper'
    WifiWand::MacHelperRelease.build_signed_helper
  end

  desc 'Test the signed helper binary'
  task :test_signed_helper do
    WifiWand::MacHelperRelease.test_signed_helper
  end

  desc 'Notarize the helper for distribution (requires Apple ID credentials)'
  task :notarize_helper do
    puts 'Tip: run via op run --env-file=.env.release -- bundle exec rake dev:notarize_helper'
    WifiWand::MacHelperRelease.notarize_helper
  end

  desc 'Complete release workflow: build, sign, test, notarize'
  task :release_helper do
    WifiWand::MacHelperRelease.release_helper
  end

  desc 'Show code signing status of helper'
  task :codesign_status do
    WifiWand::MacHelperRelease.codesign_status
  end

  desc 'Show recent notarization submissions (uses Apple ID credentials)'
  task :notarization_history do
    WifiWand::MacHelperRelease.notarization_history
  end

  desc 'Show notarization status for a submission (pass SUBMISSION_ID=<uuid>)'
  task :notarization_status do
    WifiWand::MacHelperRelease.notarization_status(fetch_submission_id)
  end

  desc 'Show notarization log for a submission (pass SUBMISSION_ID=<uuid>)'
  task :notarization_log do
    WifiWand::MacHelperRelease.notarization_log(fetch_submission_id)
  end
end

def fetch_submission_id
  submission_id = ENV['SUBMISSION_ID'] || ENV['ID'] || ENV['NOTARY_ID']
  abort 'Error: Provide SUBMISSION_ID=<notarytool-submission-id>.' if submission_id.to_s.empty?
  submission_id
end
