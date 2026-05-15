# frozen_string_literal: true

require 'rake'
require 'tmpdir'
require_relative '../spec_helper'
require_relative '../../lib/wifi_wand/platforms/mac/helper/build'

RSpec.describe 'swift:compile_helper task' do
  let(:helper) { WifiWand::Platforms::Mac::Helper::Bundle }
  let(:temp_dir) { Dir.mktmpdir('wifiwand-swift-rake-spec') }
  let(:source_root) { File.join(temp_dir, 'libexec', 'macos') }
  let(:source_bundle_path) { File.join(source_root, helper::BUNDLE_NAME) }
  let(:source_swift_path) { File.join(source_root, 'src', 'wifiwand-helper.swift') }
  let(:entitlements_path) { File.join(source_root, 'wifiwand-helper.entitlements') }
  let(:source_bundle_manifest_path) { File.join(source_root, helper::SOURCE_MANIFEST_FILENAME) }
  let(:executable_path) { File.join(source_bundle_path, 'Contents', 'MacOS', helper::EXECUTABLE_NAME) }
  let(:info_plist_path) { File.join(source_bundle_path, 'Contents', 'Info.plist') }
  let(:code_resources_path) do
    File.join(source_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
  end

  around do |example|
    original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original_rake_application
    FileUtils.rm_rf(temp_dir)
  end

  before do
    allow(RbConfig::CONFIG).to receive(:[]).and_call_original
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')

    allow(helper).to receive_messages(
      source_bundle_path:            source_bundle_path,
      source_bundle_executable_path: executable_path,
      source_swift_path:             source_swift_path,
      entitlements_path:             entitlements_path,
      source_bundle_manifest_path:   source_bundle_manifest_path,
      helper_version:                '9.9.9'
    )

    FileUtils.mkdir_p(File.dirname(source_swift_path))
    File.write(source_swift_path, "print(\"hello\")\n")
    File.write(entitlements_path, "<plist version=\"1.0\"><dict /></plist>\n")
    create_helper_bundle(source_bundle_path, help_text: 'source helper')
    helper.write_source_bundle_manifest

    load File.expand_path('../../lib/tasks/swift.rake', __dir__)
  end

  it 'skips rebuilding when the shipped helper bundle is already current' do
    expect(helper.source_bundle_current?).to be(true)
    expect(helper).not_to receive(:build_source_bundle)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'skips rebuilding when attestation is current even if mtimes look stale' do
    older_time = Time.now - 5
    newer_time = Time.now
    File.utime(older_time, older_time, executable_path)
    File.utime(newer_time, newer_time, source_swift_path)

    expect(helper.source_bundle_current?).to be(true)
    expect(helper).not_to receive(:build_source_bundle)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'rebuilds when entitlements change without a Swift source edit' do
    File.write(entitlements_path, "<plist version=\"1.0\"><dict><key>updated</key><true/></dict></plist>\n")

    expect(helper.source_bundle_current?).to be(false)
    expect(helper).to receive(:build_source_bundle).with(hash_including(:out_stream)) do |out_stream:|
      out_stream.puts 'Helper compiled and signed successfully.'
      File.write(executable_path, "#!/bin/sh\necho rebuilt\n")
      File.write(code_resources_path, "signature=rebuilt\n")
      helper.write_source_bundle_manifest
    end

    Rake::Task['swift:compile_helper'].invoke

    expect(helper.source_bundle_current?).to be(true)
  end

  it 'rebuilds when bundle template metadata changes without a Swift source edit' do
    File.write(info_plist_path, '<plist version="1.0">updated helper</plist>')

    expect(helper.source_bundle_current?).to be(false)
    expect(helper).to receive(:build_source_bundle).with(hash_including(:out_stream)) do |out_stream:|
      out_stream.puts 'Helper compiled and signed successfully.'
      File.write(executable_path, "#!/bin/sh\necho rebuilt\n")
      File.write(code_resources_path, "signature=rebuilt\n")
      helper.write_source_bundle_manifest
    end

    Rake::Task['swift:compile_helper'].invoke

    expect(helper.source_bundle_current?).to be(true)
  end

  def create_helper_bundle(bundle_path, help_text:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', helper::EXECUTABLE_NAME)
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
