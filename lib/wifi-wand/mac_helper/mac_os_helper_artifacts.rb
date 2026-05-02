# frozen_string_literal: true

require 'digest'
require 'pathname'
require_relative '../version'

module WifiWand
  module MacOsHelperBundle
    BUNDLE_NAME = 'wifiwand-helper.app'
    EXECUTABLE_NAME = 'wifiwand-helper'

    module_function def helper_version = WifiWand::VERSION

    # Returns the path to the app bundle template in the gem's libexec directory
    #
    # @return [String] absolute path to the bundle template directory
    #   Example: /path/to/gem/libexec/macos/wifiwand-helper.app
    module_function def source_bundle_path = File.expand_path(
      '../../../libexec/macos/wifiwand-helper.app', __dir__)

    module_function def source_bundle_executable_path = File.join(
      source_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME
    )

    module_function def source_swift_path = File.expand_path(
      '../../../libexec/macos/src/wifiwand-helper.swift', __dir__
    )

    module_function def entitlements_path = File.expand_path(
      '../../../libexec/macos/wifiwand-helper.entitlements', __dir__
    )

    module_function def bundle_fingerprint(bundle_path)
      digest = Digest::SHA256.new

      attested_bundle_files(bundle_path).each do |path|
        digest << relative_bundle_path(bundle_path, path)
        digest << "\0"
        digest << format('%<mode>o', mode: attested_file_mode(path))
        digest << "\0"
        digest << File.binread(path)
        digest << "\0"
      end

      digest.hexdigest
    end

    module_function def tracked_bundle_files(bundle_path) = Dir.glob(
      File.join(bundle_path, '**', '*'),
      File::FNM_DOTMATCH
    ).select { |path| File.file?(path) && !nonessential_hidden_bundle_file?(path) }.sort

    module_function def signer_generated_metadata_paths(bundle_path)
      [
        File.join(bundle_path, 'Contents', 'CodeResources'),
        File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources'),
      ]
    end

    module_function def generated_bundle_paths(bundle_path)
      signer_generated_metadata_paths(bundle_path) + [
        File.join(bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME),
      ]
    end

    module_function def attested_bundle_files(bundle_path)
      tracked_bundle_files(bundle_path) - signer_generated_metadata_paths(bundle_path)
    end

    module_function def bundle_template_input_paths(bundle_path = source_bundle_path)
      tracked_bundle_files(bundle_path) - generated_bundle_paths(bundle_path)
    end

    module_function def build_task_prerequisites
      ([source_swift_path, entitlements_path] + bundle_template_input_paths).uniq.sort
    end

    module_function def relative_helper_path(path)
      repo_root = File.expand_path('../../..', __dir__)
      Pathname.new(path).relative_path_from(Pathname.new(repo_root)).to_s
    end

    module_function def relative_bundle_path(bundle_path, path)
      Pathname.new(path).relative_path_from(Pathname.new(bundle_path)).to_s
    end

    module_function def nonessential_hidden_bundle_file?(path)
      basename = File.basename(path)
      basename == '.DS_Store' || basename.start_with?('._')
    end

    module_function def attested_file_mode(path) = File.stat(path).mode & 0o7777
  end
end
