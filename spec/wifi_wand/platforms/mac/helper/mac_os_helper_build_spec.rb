# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../../lib/wifi_wand/platforms/mac/helper/mac_os_helper_build'

RSpec.describe WifiWand::Platforms::Mac::Helper::Bundle do
  describe '.source_bundle_manifest_path' do
    it 'resolves to the repository libexec manifest next to the helper bundle' do
      expected_path = File.expand_path(
        '../../../../../libexec/macos/wifiwand-helper.source-manifest.json',
        __dir__
      )

      expect(described_class.source_bundle_manifest_path).to eq(expected_path)
    end
  end

  describe '.compile_helper' do
    let(:source_path) { '/tmp/libexec/macos/src/wifiwand-helper.swift' }
    let(:destination_path) { '/tmp/libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper' }
    let(:out_stream) { StringIO.new }
    let(:codesign_identity) { 'Developer ID Application: Example Developer (TEAM123)' }

    around do |example|
      original_identity = ENV['WIFIWAND_CODESIGN_IDENTITY']
      ENV['WIFIWAND_CODESIGN_IDENTITY'] = codesign_identity
      example.run
    ensure
      ENV['WIFIWAND_CODESIGN_IDENTITY'] = original_identity
    end

    it 'reports success only after signing finishes' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(described_class).to receive(:compile_architecture)
      allow(described_class).to receive(:create_universal_binary)
      allow(FileUtils).to receive(:rm_f)
      allow(FileUtils).to receive(:chmod)

      expect(described_class).to receive(:sign_helper_bundle)
        .with(destination_path, out_stream: out_stream) do
          out_stream.puts "Signing helper bundle with Developer ID '#{codesign_identity}'..."
        end

      described_class.compile_helper(source_path, destination_path, out_stream: out_stream)

      expect(out_stream.string).to eq(<<~OUTPUT)
        Signing helper bundle with Developer ID 'Developer ID Application: Example Developer (TEAM123)'...
        Helper compiled and signed successfully.
      OUTPUT
    end
  end

  describe '.configured_codesign_identity' do
    around do |example|
      original_identity = ENV['WIFIWAND_CODESIGN_IDENTITY']
      example.run
    ensure
      ENV['WIFIWAND_CODESIGN_IDENTITY'] = original_identity
    end

    it 'returns an override identity from the environment' do
      ENV['WIFIWAND_CODESIGN_IDENTITY'] = 'Developer ID Application: Example Developer (TEAM123)'

      expect(described_class.configured_codesign_identity)
        .to eq('Developer ID Application: Example Developer (TEAM123)')
    end

    it 'returns the official maintainer identity when the environment is unset' do
      ENV.delete('WIFIWAND_CODESIGN_IDENTITY')

      expect(described_class.configured_codesign_identity).to eq(described_class::OFFICIAL_CODESIGN_IDENTITY)
    end
  end

  describe '.configured_team_id' do
    around do |example|
      original_team_id = ENV['WIFIWAND_APPLE_TEAM_ID']
      example.run
    ensure
      ENV['WIFIWAND_APPLE_TEAM_ID'] = original_team_id
    end

    it 'returns an override Team ID from the environment' do
      ENV['WIFIWAND_APPLE_TEAM_ID'] = 'TEAM123'

      expect(described_class.configured_team_id).to eq('TEAM123')
    end

    it 'returns the official maintainer Team ID when the environment is unset' do
      ENV.delete('WIFIWAND_APPLE_TEAM_ID')

      expect(described_class.configured_team_id).to eq(described_class::OFFICIAL_APPLE_TEAM_ID)
    end
  end

  describe '.build_source_bundle' do
    let(:source_swift_path) { '/tmp/libexec/macos/src/wifiwand-helper.swift' }
    let(:source_bundle_executable_path) do
      '/tmp/libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper'
    end
    let(:out_stream) { StringIO.new }

    it 'compiles the source bundle executable and refreshes its attestation manifest' do
      allow(described_class).to receive_messages(
        source_swift_path:             source_swift_path,
        source_bundle_executable_path: source_bundle_executable_path
      )

      expect(described_class).to receive(:compile_helper)
        .with(source_swift_path, source_bundle_executable_path, out_stream: out_stream)
        .ordered
      expect(described_class).to receive(:write_source_bundle_manifest).ordered

      described_class.build_source_bundle(out_stream: out_stream)

      expect(out_stream.string).to include(
        "Compiling #{source_swift_path} -> #{source_bundle_executable_path}"
      )
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

  describe '.verify_source_bundle_signature!' do
    let(:source_bundle_path) { '/tmp/libexec/macos/wifiwand-helper.app' }
    let(:success_status) { instance_double(Process::Status, success?: true) }
    let(:failure_status) { instance_double(Process::Status, success?: false) }

    before do
      allow(described_class).to receive(:source_bundle_path).and_return(source_bundle_path)
    end

    it 'returns true when codesign verifies the committed helper bundle' do
      allow(Open3).to receive(:capture3).with(
        'codesign', '--verify', '--verbose', source_bundle_path
      ).and_return(['', '', success_status])

      expect(described_class.verify_source_bundle_signature!).to be(true)
    end

    it 'raises a rebuild hint when codesign reports an invalid signature' do
      allow(Open3).to receive(:capture3).with(
        'codesign', '--verify', '--verbose', source_bundle_path
      ).and_return(['', 'invalid signature', failure_status])

      expect do
        described_class.verify_source_bundle_signature!
      end.to raise_error(
        RuntimeError,
        /helper bundle signature is invalid.*bin\/mac-helper-release build.*invalid signature/m
      )
    end

    it 'raises a codesign requirement hint when codesign is unavailable' do
      allow(Open3).to receive(:capture3).with(
        'codesign', '--verify', '--verbose', source_bundle_path
      ).and_raise(Errno::ENOENT)

      expect do
        described_class.verify_source_bundle_signature!
      end.to raise_error(RuntimeError, /codesign is required/)
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
