# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/wifi-wand/mac_helper/mac_os_helper_build'

RSpec.describe WifiWand::MacOsHelperBundle do
  describe '.compile_helper' do
    let(:source_path) { '/tmp/libexec/macos/src/wifiwand-helper.swift' }
    let(:destination_path) { '/tmp/libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper' }
    let(:out_stream) { StringIO.new }

    it 'reports success only after signing finishes' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(described_class).to receive(:compile_architecture)
      allow(described_class).to receive(:create_universal_binary)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:chmod)

      expect(described_class).to receive(:sign_helper_bundle)
        .with(destination_path, out_stream: out_stream) do
          out_stream.puts "Signing helper bundle with Developer ID 'Developer ID Application: " \
            "Bennett Business Solutions, Inc. (97P9SZU9GG)'..."
        end

      described_class.compile_helper(source_path, destination_path, out_stream: out_stream)

      expect(out_stream.string).to eq(<<~OUTPUT)
        Signing helper bundle with Developer ID 'Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)'...
        Helper compiled and signed successfully.
      OUTPUT
    end
  end

  describe '.source_bundle_current?' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-source-spec') }
    let(:source_root) { File.join(temp_dir, 'libexec', 'macos') }
    let(:source_bundle_path) { File.join(source_root, described_class::BUNDLE_NAME) }
    let(:source_swift_path) { File.join(source_root, 'src', 'wifiwand-helper.swift') }
    let(:entitlements_path) { File.join(source_root, 'wifiwand-helper.entitlements') }
    let(:source_bundle_manifest_path) do
      File.join(source_root, described_class::SOURCE_MANIFEST_FILENAME)
    end

    before do
      allow(described_class).to receive_messages(
        source_bundle_path:          source_bundle_path,
        source_swift_path:           source_swift_path,
        entitlements_path:           entitlements_path,
        source_bundle_manifest_path: source_bundle_manifest_path,
        helper_version:              '9.9.9'
      )

      FileUtils.mkdir_p(File.dirname(source_swift_path))
      File.write(source_swift_path, "print(\"hello\")\n")
      File.write(entitlements_path, "<plist version=\"1.0\"><dict /></plist>\n")
      create_helper_bundle(source_bundle_path, help_text: 'source helper')
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'returns true when the committed source manifest matches the current source and bundle' do
      described_class.write_source_bundle_manifest

      expect(described_class.source_bundle_current?).to be(true)
      expect(JSON.parse(File.read(source_bundle_manifest_path))).to include(
        'helper_version'      => '9.9.9',
        'source_path'         => described_class.send(:relative_helper_path, source_swift_path),
        'entitlements_path'   => described_class.send(:relative_helper_path, entitlements_path),
        'bundle_path'         => described_class.send(:relative_helper_path, source_bundle_path),
        'source_sha256'       => described_class.source_swift_fingerprint,
        'entitlements_sha256' => described_class.entitlements_fingerprint,
        'bundle_fingerprint'  => described_class.bundle_fingerprint(source_bundle_path)
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

    it 'returns false when entitlements change after the manifest was generated' do
      described_class.write_source_bundle_manifest
      File.write(entitlements_path, "<plist version=\"1.0\"><dict><key>updated</key><true/></dict></plist>\n")

      expect(described_class.source_bundle_current?).to be(false)
    end

    it 'raises a rebuild hint when the manifest no longer matches the committed source or bundle' do
      described_class.write_source_bundle_manifest
      File.write(source_swift_path, "print(\"updated\")\n")

      expect do
        described_class.verify_source_bundle_current!
      end.to raise_error(
        RuntimeError,
        /committed helper source, entitlements, or bundle contents.*bundle exec rake swift:compile_helper/m
      )
    end
  end

  def create_helper_bundle(bundle_path, help_text:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    legacy_code_resources_path = File.join(bundle_path, 'Contents', 'CodeResources')
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

    FileUtils.mkdir_p(File.dirname(legacy_code_resources_path))
    File.write(legacy_code_resources_path, "legacy-signature=#{help_text}\n")

    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=#{help_text}\n")
  end
end
