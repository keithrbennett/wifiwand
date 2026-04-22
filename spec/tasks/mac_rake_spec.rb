# frozen_string_literal: true

require_relative '../spec_helper'
require 'rake'
require 'stringio'

RSpec.describe 'mac rake tasks' do
  let(:rake) { Rake::Application.new }
  let(:task_path) { File.expand_path('../../lib/tasks/mac.rake', __dir__) }
  let(:helper) { WifiWand::MacOsWifiAuthHelper }

  before do
    Rake.application = rake
    load task_path
    rake['mac:public_signing_info'].reenable
    rake['mac:store_notarytool_credentials'].reenable
    allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin24')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with(
      'WIFIWAND_NOTARYTOOL_PROFILE',
      WifiWand::MacHelperRelease::DEFAULT_NOTARYTOOL_PROFILE
    ).and_return('custom-profile')
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WIFIWAND_APPLE_DEV_ID').and_return('dev@example.com')
    allow(ENV).to receive(:[]).with('WIFIWAND_NOTARYTOOL_KEYCHAIN').and_return('/tmp/custom.keychain-db')
  end

  after do
    rake.clear
  end

  it 'prints only public signing and notarization metadata' do
    expected_executable = File.join(helper.source_bundle_path, 'Contents', 'MacOS', helper::EXECUTABLE_NAME)

    expect { rake['mac:public_signing_info'].invoke }.to output(
      a_string_including(
        'Public macOS signing and notarization info:',
        "Team ID: #{WifiWand::MacHelperRelease::APPLE_TEAM_ID}",
        "Codesign identity: #{WifiWand::MacHelperRelease::CODESIGN_IDENTITY}",
        'Notarytool profile: custom-profile',
        'Keychain path: /tmp/custom.keychain-db',
        "Helper bundle path: #{helper.source_bundle_path}",
        "Helper executable path: #{expected_executable}"
      )
    ).to_stdout
  end

  it 'runs notarytool store-credentials with public configuration and interactive password entry' do
    expect(Kernel).to receive(:system).with(
      'xcrun',
      'notarytool',
      'store-credentials',
      'custom-profile',
      '--apple-id',
      'dev@example.com',
      '--team-id',
      WifiWand::MacHelperRelease::APPLE_TEAM_ID,
      '--keychain',
      '/tmp/custom.keychain-db'
    ).and_return(true)

    expect { rake['mac:store_notarytool_credentials'].invoke }.to output(
      a_string_including(
        'Storing notarytool credentials in the keychain...',
        'Profile: custom-profile',
        'Apple ID: dev@example.com',
        "Team ID: #{WifiWand::MacHelperRelease::APPLE_TEAM_ID}",
        'Keychain path: /tmp/custom.keychain-db',
        'notarytool will prompt for the app-specific password.'
      )
    ).to_stdout
  end

  it 'prompts for the Apple ID when the environment variable is missing' do
    rake['mac:store_notarytool_credentials'].reenable
    allow(ENV).to receive(:[]).with('WIFIWAND_APPLE_DEV_ID').and_return(nil)
    allow($stdin).to receive(:gets).and_return("prompted@example.com\n")

    expect(Kernel).to receive(:system).with(
      'xcrun',
      'notarytool',
      'store-credentials',
      'custom-profile',
      '--apple-id',
      'prompted@example.com',
      '--team-id',
      WifiWand::MacHelperRelease::APPLE_TEAM_ID,
      '--keychain',
      '/tmp/custom.keychain-db'
    ).and_return(true)

    expect { rake['mac:store_notarytool_credentials'].invoke }.to output(
      a_string_including(
        'Apple ID email for notarytool: ',
        'Apple ID: prompted@example.com'
      )
    ).to_stdout
  end
end
