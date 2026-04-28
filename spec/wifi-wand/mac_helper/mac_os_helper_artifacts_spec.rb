# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/wifi-wand/mac_helper/mac_os_helper_artifacts'

RSpec.describe WifiWand::MacOsHelperBundle do
  describe '.bundle_fingerprint' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-artifacts-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'hashes the tracked bundle files, including binary executable contents' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)

      original_fingerprint = described_class.bundle_fingerprint(bundle_path)
      File.binwrite(
        File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME),
        "MZ\x00\xFEwifiwand".b
      )

      expect(described_class.bundle_fingerprint(bundle_path)).not_to eq(original_fingerprint)
    end
  end

  describe '.tracked_bundle_files' do
    it 'returns the bundle files that define the shipped helper artifact' do
      bundle_path = '/tmp/wifiwand-helper.app'

      expect(described_class.tracked_bundle_files(bundle_path)).to eq([
        "#{bundle_path}/Contents/Info.plist",
        "#{bundle_path}/Contents/_CodeSignature/CodeResources",
        "#{bundle_path}/Contents/MacOS/#{described_class::EXECUTABLE_NAME}",
      ])
    end
  end

  describe '.relative_helper_path' do
    it 'returns repo-relative paths for helper artifacts' do
      repo_path = File.expand_path('../../../libexec/macos/wifiwand-helper.app', __dir__)

      expect(described_class.send(:relative_helper_path, repo_path))
        .to eq('libexec/macos/wifiwand-helper.app')
    end
  end

  def create_helper_bundle(bundle_path, executable_bytes:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    info_plist_path = File.join(bundle_path, 'Contents', 'Info.plist')
    code_resources_path = File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    FileUtils.mkdir_p(File.dirname(executable_path))
    File.binwrite(executable_path, executable_bytes)
    FileUtils.chmod(0o755, executable_path)

    FileUtils.mkdir_p(File.dirname(info_plist_path))
    File.write(info_plist_path, '<plist version="1.0">helper</plist>')

    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=helper\n")
  end
end
