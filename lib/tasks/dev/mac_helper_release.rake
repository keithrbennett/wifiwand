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
  desc 'Build and sign helper with Developer ID (for gem distribution)'
  task :build_signed_helper do
    WifiWand::MacHelperRelease.build_signed_helper
  end

  desc 'Test the signed helper binary'
  task :test_signed_helper do
    WifiWand::MacHelperRelease.test_signed_helper
  end

  desc 'Notarize the helper for distribution (requires Apple ID credentials)'
  task :notarize_helper do
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
end
