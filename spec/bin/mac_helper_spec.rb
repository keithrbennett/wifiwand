# frozen_string_literal: true

require_relative '../spec_helper'
require 'open3'
require 'rbconfig'
load File.expand_path('../../bin/mac-helper-release', __dir__)

MAC_HELPER_PATH = File.expand_path('../../bin/mac-helper-release', __dir__)

RSpec.describe 'bin/mac-helper-release' do
  def run_mac_helper(argv:, chdir:, command_path: MAC_HELPER_PATH, env: {})
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, command_path, *argv, chdir:)
    { stdout:, stderr:, exit_code: status.exitstatus }
  end

  describe MacHelperCLI::CLI do
    def build_cli(argv)
      described_class.new(argv)
    end

    def stub_release_selection(_cli)
      allow(WifiWand::Platforms::Mac::Helper::Release).to receive(:normalize_submission_order) { |order| order }
    end

    it 'defaults cancel to the oldest pending submission' do
      cli = build_cli(['cancel'])
      stub_release_selection(cli)

      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:select_submission_id)
        .with(order: :asc, pending_only: true)
        .and_return('pending-001')
      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:cancel_notarization).with('pending-001')

      expect { cli.run }
        .to output(/using oldest pending notary submission pending-001/).to_stdout
    end

    it 'defaults info to the latest submission' do
      cli = build_cli(['info'])
      stub_release_selection(cli)

      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:select_submission_id)
        .with(order: :desc, pending_only: false)
        .and_return('latest-001')
      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:notarization_status).with('latest-001')

      expect { cli.run }
        .to output(/using latest notary submission latest-001/).to_stdout
    end

    it 'defaults log to the latest submission' do
      cli = build_cli(['log'])
      stub_release_selection(cli)

      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:select_submission_id)
        .with(order: :desc, pending_only: false)
        .and_return('latest-002')
      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:notarization_log).with('latest-002')

      expect { cli.run }
        .to output(/using latest notary submission latest-002/).to_stdout
    end

    it 'lets an explicit order flag override cancel ordering without clearing pending_only' do
      cli = build_cli(['cancel', '--order', 'desc'])
      stub_release_selection(cli)

      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:select_submission_id)
        .with(order: :desc, pending_only: true)
        .and_return('pending-override')
      expect(WifiWand::Platforms::Mac::Helper::Release)
        .to receive(:cancel_notarization).with('pending-override')

      expect { cli.run }
        .to output(/using latest pending notary submission pending-override/).to_stdout
    end

    it 'lets an explicit pending-only flag override info selection' do
      cli = build_cli(['info', '--pending-only'])
      stub_release_selection(cli)

      expect(WifiWand::Platforms::Mac::Helper::Release).to receive(:select_submission_id)
        .with(order: :desc, pending_only: true)
        .and_return('latest-pending')
      expect(WifiWand::Platforms::Mac::Helper::Release)
        .to receive(:notarization_status).with('latest-pending')

      expect { cli.run }
        .to output(/using latest pending notary submission latest-pending/).to_stdout
    end

    it 'prints public signing info' do
      cli = build_cli(['public-info'])
      helper = WifiWand::Platforms::Mac::Helper::Bundle
      helper_exec_path = File.join(helper.source_bundle_path, 'Contents', 'MacOS', helper::EXECUTABLE_NAME)

      allow(WifiWand::Platforms::Mac::Helper::Release::Operations).to receive(:require_macos!)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with(
        'WIFIWAND_NOTARYTOOL_PROFILE',
        WifiWand::Platforms::Mac::Helper::Release::DEFAULT_NOTARYTOOL_PROFILE
      ).and_return('custom-profile')
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_NOTARYTOOL_KEYCHAIN').and_return('/tmp/custom.keychain-db')
      allow(WifiWand::Platforms::Mac::Helper::Release).to receive_messages(
        configured_team_id:           'TEAM123',
        configured_codesign_identity: 'Developer ID Application: Example Developer (TEAM123)'
      )

      expect { cli.run }.to output(
        a_string_including(
          'Public macOS signing and notarization info:',
          'Team ID: TEAM123',
          'Codesign identity: Developer ID Application: Example Developer (TEAM123)',
          'Notarytool profile: custom-profile',
          'Keychain path: /tmp/custom.keychain-db',
          "Helper bundle path: #{helper.source_bundle_path}",
          "Helper executable path: #{helper_exec_path}"
        )
      ).to_stdout
    end

    it 'stores notarytool credentials using the configured Apple ID' do
      cli = build_cli(['store-credentials'])

      allow(WifiWand::Platforms::Mac::Helper::Release::Operations).to receive(:require_macos!)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with(
        'WIFIWAND_NOTARYTOOL_PROFILE',
        WifiWand::Platforms::Mac::Helper::Release::DEFAULT_NOTARYTOOL_PROFILE
      ).and_return('custom-profile')
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_APPLE_DEV_ID').and_return('dev@example.com')
      allow(ENV).to receive(:[]).with('WIFIWAND_NOTARYTOOL_KEYCHAIN').and_return('/tmp/custom.keychain-db')
      allow(WifiWand::Platforms::Mac::Helper::Release).to receive(:configured_team_id).and_return('TEAM123')
      allow(WifiWand::Platforms::Mac::Helper::Release::Operations).to receive(:verify_team_id_configured)
      expect(cli).to receive(:system).with(
        'xcrun',
        'notarytool',
        'store-credentials',
        'custom-profile',
        '--apple-id',
        'dev@example.com',
        '--team-id',
        'TEAM123',
        '--keychain',
        '/tmp/custom.keychain-db'
      ).and_return(true)

      expect { cli.run }.to output(
        a_string_including(
          'Storing notarytool credentials in the keychain...',
          'Profile: custom-profile',
          'Apple ID: dev@example.com',
          'Team ID: TEAM123',
          'Keychain path: /tmp/custom.keychain-db',
          'notarytool will prompt for the app-specific password.'
        )
      ).to_stdout
    end

    it 'prompts for the Apple ID when store-credentials is missing the environment variable' do
      cli = build_cli(['store-credentials'])

      allow(WifiWand::Platforms::Mac::Helper::Release::Operations).to receive(:require_macos!)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with(
        'WIFIWAND_NOTARYTOOL_PROFILE',
        WifiWand::Platforms::Mac::Helper::Release::DEFAULT_NOTARYTOOL_PROFILE
      ).and_return('custom-profile')
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_APPLE_DEV_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('WIFIWAND_NOTARYTOOL_KEYCHAIN').and_return('/tmp/custom.keychain-db')
      allow($stdin).to receive(:gets).and_return("prompted@example.com\n")
      allow(WifiWand::Platforms::Mac::Helper::Release).to receive(:configured_team_id).and_return('TEAM123')
      allow(WifiWand::Platforms::Mac::Helper::Release::Operations).to receive(:verify_team_id_configured)
      expect(cli).to receive(:system).with(
        'xcrun',
        'notarytool',
        'store-credentials',
        'custom-profile',
        '--apple-id',
        'prompted@example.com',
        '--team-id',
        'TEAM123',
        '--keychain',
        '/tmp/custom.keychain-db'
      ).and_return(true)

      expect { cli.run }.to output(
        a_string_including(
          'Apple ID email for notarytool: ',
          'Apple ID: prompted@example.com'
        )
      ).to_stdout
    end
  end

  it 'documents the secure notarytool profile workflow in help output' do
    result = run_mac_helper(argv: ['help'], chdir: Dir.pwd)

    expect(result[:exit_code]).to eq(0)
    expect(result[:stderr]).to eq('')
    expect(result[:stdout]).to include('bin/mac-helper-release store-credentials')
    expect(result[:stdout]).to include('WIFIWAND_NOTARYTOOL_PROFILE')
    expect(result[:stdout]).to include('WIFIWAND_APPLE_TEAM_ID')
    expect(result[:stdout]).to include('WIFIWAND_CODESIGN_IDENTITY')
    expect(result[:stdout]).to include('bin/mac-helper-release public-info')
    expect(result[:stdout]).to include('bin/mac-helper-release store-credentials')
    expect(result[:stdout]).to include('dev/docs/MACOS_CODE_SIGNING_INSTRUCTIONS.md')
    expect(result[:stdout]).to include('dev/docs/MACOS_CODE_SIGNING_CONTEXT.md')
    expect(result[:stdout]).not_to include('docs/dev/')
    expect(result[:stdout]).not_to include('WIFIWAND_APPLE_DEV_PASSWORD')
  end
end
