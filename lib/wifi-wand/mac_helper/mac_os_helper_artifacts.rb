# frozen_string_literal: true

require 'digest'
require 'pathname'
require_relative '../version'

module WifiWand
  module MacOsWifiAuthHelper
    BUNDLE_NAME = 'wifiwand-helper.app'
    EXECUTABLE_NAME = 'wifiwand-helper'

    module_function def helper_version = WifiWand::VERSION

    # Returns the path to the app bundle template in the gem's libexec directory
    #
    # @return [String] absolute path to the bundle template directory
    #   Example: /path/to/gem/libexec/macos/wifiwand-helper.app
    module_function def source_bundle_path = File.expand_path(
      '../../../libexec/macos/wifiwand-helper.app', __dir__)

    module_function def bundle_fingerprint(bundle_path)
      digest = Digest::SHA256.new

      tracked_bundle_files(bundle_path).each do |path|
        digest << File.basename(path)
        digest << "\0"
        digest << File.binread(path)
        digest << "\0"
      end

      digest.hexdigest
    end

    module_function def tracked_bundle_files(bundle_path)
      [
        File.join(bundle_path, 'Contents', 'Info.plist'),
        File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources'),
        File.join(bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME),
      ]
    end

    module_function def relative_helper_path(path)
      repo_root = File.expand_path('../../..', __dir__)
      Pathname.new(path).relative_path_from(Pathname.new(repo_root)).to_s
    end
  end
end
