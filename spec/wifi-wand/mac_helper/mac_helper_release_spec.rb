# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/mac_helper/mac_helper_release'

RSpec.describe WifiWand::MacHelperRelease do
  let(:creds) do
    {
      profile_name:  'wifiwand-notarytool',
      keychain_path: nil,
      team_id:       'TEAM123',
    }
  end
  let(:signing_instructions_path) { described_class::SIGNING_INSTRUCTIONS_PATH }

  def expect_system_exit_with_stderr(pattern, &block)
    # `abort` writes to stderr and then raises SystemExit. We wrap the
    # `raise_error` expectation so the outer matcher can assert on stderr
    # without swallowing the exit behavior we also want to verify.
    expect do
      expect(&block).to raise_error(SystemExit)
    end.to output(pattern).to_stderr
  end

  describe 'signing configuration guidance' do
    it 'points unconfigured codesign identity failures at the maintained instructions' do
      expect_system_exit_with_stderr(
        /See #{Regexp.escape(signing_instructions_path)} for detailed instructions\./
      ) do
        described_class::Operations.verify_identity_configured(
          'Developer ID Application: Your Name (YOUR_TEAM_ID_HERE)'
        )
      end
    end

    it 'points unconfigured team ID failures at the maintained instructions' do
      expect_system_exit_with_stderr(
        /See #{Regexp.escape(signing_instructions_path)} for detailed instructions\./
      ) do
        described_class::Operations.verify_team_id_configured('YOUR_TEAM_ID_HERE')
      end
    end

    it 'points missing notarization credentials failures at the maintained instructions' do
      expect_system_exit_with_stderr(
        /See #{Regexp.escape(signing_instructions_path)} for detailed instructions\./
      ) do
        described_class::Operations.verify_credentials('', 'TEAM123', command_hint: 'bin/mac-helper notarize')
      end
    end
  end

  describe '.fetch_notary_credentials!' do
    around do |example|
      original_profile = ENV['WIFIWAND_NOTARYTOOL_PROFILE']
      original_keychain = ENV['WIFIWAND_NOTARYTOOL_KEYCHAIN']
      ENV.delete('WIFIWAND_NOTARYTOOL_PROFILE')
      ENV.delete('WIFIWAND_NOTARYTOOL_KEYCHAIN')
      example.run
    ensure
      ENV['WIFIWAND_NOTARYTOOL_PROFILE'] = original_profile
      ENV['WIFIWAND_NOTARYTOOL_KEYCHAIN'] = original_keychain
    end

    it 'defaults to the checked-in notarytool profile name' do
      allow(described_class::Operations).to receive(:verify_team_id_configured)
      allow(described_class::Operations).to receive(:verify_credentials)

      expect(described_class.fetch_notary_credentials!(command_hint: 'bin/mac-helper notarize')).to eq(
        profile_name:  described_class::DEFAULT_NOTARYTOOL_PROFILE,
        keychain_path: nil,
        team_id:       described_class::APPLE_TEAM_ID
      )
    end
  end

  describe '.run_notarytool' do
    it 'uses the keychain profile and never appends a raw password argument' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'xcrun', 'notarytool', 'history', '--keychain-profile', 'wifiwand-notarytool'
      ).and_return(['', '', status])

      described_class::Operations.run_notarytool(
        ['history'],
        profile_name:    'wifiwand-notarytool',
        keychain_path:   nil,
        team_id:         'TEAM123',
        failure_message: 'Unable to fetch notarization history.'
      )
    end
  end

  describe '.cancel_notarization' do
    before do
      allow(described_class).to receive(:fetch_notary_credentials!).and_return(creds)
    end

    it 'succeeds for a pending submission' do
      expect(described_class::Operations).to receive(:run_notarytool).ordered.with(
        ['history', '--output-format', 'json'],
        **creds,
        failure_message: 'Unable to fetch notarization history.',
        suppress_output: true
      ).and_return(
        JSON.generate('history' => [{ 'id' => 'pending-001', 'status' => 'In Progress' }])
      )
      expect(described_class::Operations).to receive(:run_notarytool).ordered.with(
        %w[queue remove pending-001],
        **creds,
        failure_message: 'Unable to cancel notarization request.'
      ).and_return('')

      expect { described_class.cancel_notarization('pending-001') }
        .to output(/Canceling submission pending-001.*removed from notary queue/m).to_stdout
    end

    it 'rejects a non-pending submission' do
      expect(described_class::Operations).to receive(:run_notarytool).with(
        ['history', '--output-format', 'json'],
        **creds,
        failure_message: 'Unable to fetch notarization history.',
        suppress_output: true
      ).and_return(
        JSON.generate('history' => [{ 'id' => 'accepted-001', 'status' => 'Accepted' }])
      )
      expect(described_class::Operations).not_to receive(:run_notarytool).with(
        %w[queue remove accepted-001],
        any_args
      )

      expect_system_exit_with_stderr(/Submission accepted-001 is Accepted and cannot be canceled/) do
        described_class.cancel_notarization('accepted-001')
      end
    end

    it 'rejects an explicit submission ID that is not pending' do
      expect(described_class::Operations).to receive(:run_notarytool).with(
        ['history', '--output-format', 'json'],
        **creds,
        failure_message: 'Unable to fetch notarization history.',
        suppress_output: true
      ).and_return(
        JSON.generate('history' => [{ 'id' => 'explicit-001', 'status' => 'Invalid' }])
      )
      expect(described_class::Operations).not_to receive(:run_notarytool).with(
        %w[queue remove explicit-001],
        any_args
      )

      expect_system_exit_with_stderr(/Submission explicit-001 is Invalid and cannot be canceled/) do
        described_class.cancel_notarization('explicit-001')
      end
    end

    it 'rejects a submission ID that is missing from history' do
      expect(described_class::Operations).to receive(:run_notarytool).with(
        ['history', '--output-format', 'json'],
        **creds,
        failure_message: 'Unable to fetch notarization history.',
        suppress_output: true
      ).and_return(
        JSON.generate('history' => [{ 'id' => 'other-001', 'status' => 'In Progress' }])
      )
      expect(described_class::Operations).not_to receive(:run_notarytool).with(
        %w[queue remove missing-001],
        any_args
      )

      expect_system_exit_with_stderr(
        /Submission missing-001 was not found in notarization history.*Run: bin\/mac-helper history/m
      ) do
        described_class.cancel_notarization('missing-001')
      end
    end
  end
end
