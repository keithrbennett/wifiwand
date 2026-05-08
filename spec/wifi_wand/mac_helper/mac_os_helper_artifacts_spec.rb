# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/wifi_wand/mac_helper/mac_os_helper_artifacts'

RSpec.describe WifiWand::MacOsHelperBundle do
  describe '.build_task_prerequisites' do
    it 'is defined entirely from artifact-owned paths and bundle inputs' do
      messages = {
        source_swift_path:           '/tmp/libexec/macos/src/wifiwand-helper.swift',
        entitlements_path:           '/tmp/libexec/macos/wifiwand-helper.entitlements',
        bundle_template_input_paths: [
          '/tmp/libexec/macos/wifiwand-helper.app/Contents/Info.plist',
          '/tmp/libexec/macos/wifiwand-helper.app/Contents/Resources/icon.icns',
        ],
      }

      allow(described_class).to receive_messages(messages)

      expect(described_class.build_task_prerequisites).to eq([
        '/tmp/libexec/macos/src/wifiwand-helper.swift',
        '/tmp/libexec/macos/wifiwand-helper.app/Contents/Info.plist',
        '/tmp/libexec/macos/wifiwand-helper.app/Contents/Resources/icon.icns',
        '/tmp/libexec/macos/wifiwand-helper.entitlements',
      ])
    end
  end

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

    it 'changes when the executable mode changes' do
      executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)

      original_fingerprint = described_class.bundle_fingerprint(bundle_path)
      FileUtils.chmod(0o644, executable_path)

      expect(described_class.bundle_fingerprint(bundle_path)).not_to eq(original_fingerprint)
    end

    it 'ignores signer-generated metadata when fingerprinting the bundle' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)

      original_fingerprint = described_class.bundle_fingerprint(bundle_path)
      File.write(File.join(bundle_path, 'Contents', 'CodeResources'), 'updated-legacy-signature')
      File.write(File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources'),
        'updated-signature')

      expect(described_class.bundle_fingerprint(bundle_path)).to eq(original_fingerprint)
    end

    it 'ignores non-essential hidden macOS files when fingerprinting the bundle' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)

      original_fingerprint = described_class.bundle_fingerprint(bundle_path)
      File.write(File.join(bundle_path, 'Contents', '.DS_Store'), 'finder-noise')
      File.write(File.join(bundle_path, 'Contents', '._CodeResources'), 'appledouble-noise')

      expect(described_class.bundle_fingerprint(bundle_path)).to eq(original_fingerprint)
    end
  end

  describe '.tracked_bundle_files' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-artifacts-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns the bundle files that define the shipped helper artifact' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)
      File.write(File.join(bundle_path, 'Contents', 'CodeResources'), 'legacy-signature')
      File.write(File.join(bundle_path, 'Contents', 'Resources', 'wifiwand-helper.icns'), 'icon')
      File.write(File.join(bundle_path, 'Contents', '.DS_Store'), 'finder-noise')
      File.write(File.join(bundle_path, 'Contents', 'Resources', '._wifiwand-helper.icns'),
        'appledouble-noise')

      expect(described_class.tracked_bundle_files(bundle_path)).to eq([
        "#{bundle_path}/Contents/CodeResources",
        "#{bundle_path}/Contents/Info.plist",
        "#{bundle_path}/Contents/MacOS/#{described_class::EXECUTABLE_NAME}",
        "#{bundle_path}/Contents/Resources/wifiwand-helper.icns",
        "#{bundle_path}/Contents/_CodeSignature/CodeResources",
      ])
    end
  end

  describe '.bundle_template_input_paths' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-artifacts-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'excludes generated signing outputs and the compiled executable' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)
      File.write(File.join(bundle_path, 'Contents', 'CodeResources'), 'legacy-signature')
      File.write(File.join(bundle_path, 'Contents', 'Resources', 'wifiwand-helper.icns'), 'icon')

      expect(described_class.bundle_template_input_paths(bundle_path)).to eq([
        "#{bundle_path}/Contents/Info.plist",
        "#{bundle_path}/Contents/Resources/wifiwand-helper.icns",
      ])
    end
  end

  describe '.attested_bundle_files' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-artifacts-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'excludes signer-generated metadata but keeps the executable in attestation' do
      create_helper_bundle(bundle_path, executable_bytes: "MZ\x00\xFFwifiwand".b)
      File.write(File.join(bundle_path, 'Contents', 'CodeResources'), 'legacy-signature')
      File.write(File.join(bundle_path, 'Contents', 'Resources', 'wifiwand-helper.icns'), 'icon')

      expect(described_class.attested_bundle_files(bundle_path)).to eq([
        "#{bundle_path}/Contents/Info.plist",
        "#{bundle_path}/Contents/MacOS/#{described_class::EXECUTABLE_NAME}",
        "#{bundle_path}/Contents/Resources/wifiwand-helper.icns",
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
    legacy_code_resources_path = File.join(bundle_path, 'Contents', 'CodeResources')
    info_plist_path = File.join(bundle_path, 'Contents', 'Info.plist')
    code_resources_path = File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
    resources_dir = File.join(bundle_path, 'Contents', 'Resources')

    FileUtils.mkdir_p(File.dirname(executable_path))
    File.binwrite(executable_path, executable_bytes)
    FileUtils.chmod(0o755, executable_path)

    FileUtils.mkdir_p(File.dirname(info_plist_path))
    File.write(info_plist_path, '<plist version="1.0">helper</plist>')

    FileUtils.mkdir_p(File.dirname(legacy_code_resources_path))
    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=helper\n")

    FileUtils.mkdir_p(resources_dir)
  end
end
