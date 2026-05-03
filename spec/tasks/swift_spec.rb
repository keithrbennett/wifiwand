# frozen_string_literal: true

require 'rake'
require 'spec_helper'

RSpec.describe 'swift tasks' do
  let(:helper) { WifiWand::MacOsHelperBundle }
  let(:bundle_path) { '/tmp/wifiwand-helper.app' }
  let(:helper_binary) do
    File.join(bundle_path, 'Contents', 'MacOS', WifiWand::MacOsHelperBundle::EXECUTABLE_NAME)
  end

  around do |example|
    previous_rake_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = previous_rake_application
  end

  before do
    allow(helper).to receive(:source_bundle_executable_path).and_return(helper_binary)
    load File.expand_path('../../lib/tasks/swift.rake', __dir__)
  end

  it 'skips rebuilding when the shipped helper exists and attestation is current' do
    allow(File).to receive(:exist?).with(helper_binary).and_return(true)
    allow(helper).to receive(:source_bundle_current?).and_return(true)
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux')

    expect(helper).not_to receive(:build_source_bundle)
    expect(helper).not_to receive(:verify_source_bundle_current!)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'rebuilds when the shipped helper is missing' do
    allow(File).to receive(:exist?).with(helper_binary).and_return(false)
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')

    expect(helper).not_to receive(:source_bundle_current?)
    expect(helper).to receive(:build_source_bundle).with(out_stream: $stdout)
    expect(helper).to receive(:verify_source_bundle_current!)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'rebuilds when attestation says the shipped helper is stale' do
    allow(File).to receive(:exist?).with(helper_binary).and_return(true)
    allow(helper).to receive(:source_bundle_current?).and_return(false)
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')

    expect(helper).to receive(:build_source_bundle).with(out_stream: $stdout)
    expect(helper).to receive(:verify_source_bundle_current!)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'rebuilds when attestation cannot read part of the shipped helper bundle' do
    allow(File).to receive(:exist?).with(helper_binary).and_return(true)
    allow(helper).to receive(:source_bundle_current?).and_raise(Errno::ENOENT)
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin')

    expect(helper).to receive(:build_source_bundle).with(out_stream: $stdout)
    expect(helper).to receive(:verify_source_bundle_current!)

    Rake::Task['swift:compile_helper'].invoke
  end

  it 'requires macOS only when a rebuild is needed' do
    allow(File).to receive(:exist?).with(helper_binary).and_return(false)
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux')

    expect(helper).not_to receive(:build_source_bundle)
    expect(helper).not_to receive(:verify_source_bundle_current!)

    expect do
      Rake::Task['swift:compile_helper'].invoke
    end.to raise_error(SystemExit)
  end
end
