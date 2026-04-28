# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/wifi-wand/mac_helper/mac_os_helper_build'

RSpec.describe WifiWand::MacOsHelperBundle do
  describe '.source_bundle_current?' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-source-spec') }
    let(:source_root) { File.join(temp_dir, 'libexec', 'macos') }
    let(:source_bundle_path) { File.join(source_root, described_class::BUNDLE_NAME) }
    let(:source_swift_path) { File.join(source_root, 'src', 'wifiwand-helper.swift') }
    let(:source_bundle_manifest_path) do
      File.join(source_root, described_class::SOURCE_MANIFEST_FILENAME)
    end

    before do
      allow(described_class).to receive_messages(
        source_bundle_path:          source_bundle_path,
        source_swift_path:           source_swift_path,
        source_bundle_manifest_path: source_bundle_manifest_path,
        helper_version:              '9.9.9'
      )

      FileUtils.mkdir_p(File.dirname(source_swift_path))
      File.write(source_swift_path, "print(\"hello\")\n")
      create_helper_bundle(source_bundle_path, help_text: 'source helper')
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns true when the committed source manifest matches the current source and bundle' do
      described_class.write_source_bundle_manifest

      expect(described_class.source_bundle_current?).to be(true)
      expect(JSON.parse(File.read(source_bundle_manifest_path))).to include(
        'helper_version'     => '9.9.9',
        'source_path'        => described_class.send(:relative_helper_path, source_swift_path),
        'bundle_path'        => described_class.send(:relative_helper_path, source_bundle_path),
        'source_sha256'      => described_class.source_swift_fingerprint,
        'bundle_fingerprint' => described_class.bundle_fingerprint(source_bundle_path)
      )
    end

    it 'returns false when the swift source changes after the manifest was generated' do
      described_class.write_source_bundle_manifest
      File.write(source_swift_path, "print(\"updated\")\n")

      expect(described_class.source_bundle_current?).to be(false)
    end

    it 'returns false when the shipped bundle changes after the manifest was generated' do
      described_class.write_source_bundle_manifest
      File.write(File.join(source_bundle_path, 'Contents', 'Info.plist'), '<plist>updated</plist>')

      expect(described_class.source_bundle_current?).to be(false)
    end

    it 'raises a rebuild hint when the manifest no longer matches the committed source or bundle' do
      described_class.write_source_bundle_manifest
      File.write(source_swift_path, "print(\"updated\")\n")

      expect do
        described_class.verify_source_bundle_current!
      end.to raise_error(RuntimeError, /bundle exec rake swift:compile/)
    end
  end

  def create_helper_bundle(bundle_path, help_text:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    info_plist_path = File.join(bundle_path, 'Contents', 'Info.plist')
    code_resources_path = File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    FileUtils.mkdir_p(File.dirname(executable_path))
    File.write(executable_path, <<~SH)
      #!/bin/sh
      echo "#{help_text}"
      SH
    FileUtils.chmod(0o755, executable_path)

    FileUtils.mkdir_p(File.dirname(info_plist_path))
    File.write(info_plist_path, "<plist version=\"1.0\">#{help_text}</plist>")

    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=#{help_text}\n")
  end
end
