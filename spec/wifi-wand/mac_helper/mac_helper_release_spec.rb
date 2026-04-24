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

  describe '.notarize_helper' do
    let(:bundle_path) { '/tmp/wifiwand-helper.app' }
    let(:zip_path) { "#{bundle_path}.zip" }
    let(:codesign_status) { instance_double(Process::Status, success?: true) }
    let(:codesign_failure_status) { instance_double(Process::Status, success?: false) }
    let(:developer_id_signature) do
      <<~OUTPUT
        Executable=#{bundle_path}/Contents/MacOS/wifiwand-helper
        Authority=Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)
      OUTPUT
    end

    before do
      allow(described_class::Operations).to receive(:require_macos!)
      allow(described_class).to receive(:fetch_notary_credentials!).and_return(creds)
      allow(described_class).to receive(:verify_source_attestation!)
      allow(WifiWand::MacOsWifiAuthHelper).to receive(:source_bundle_path).and_return(bundle_path)
      allow(File).to receive(:exist?).with(bundle_path).and_return(true)
    end

    it 'aborts before notarization work when codesign exits non-zero (unsigned binary)' do
      allow(Open3).to receive(:capture3).with('codesign', '-dv', bundle_path).and_return(
        ['', "#{bundle_path}: code object is not signed at all\n", codesign_failure_status]
      )
      allow(described_class::Operations).to receive(:create_zip)
      allow(described_class::Operations).to receive(:submit_for_notarization)

      expect_system_exit_with_stderr(
        /Could not inspect code signature.*code object is not signed.*bin\/mac-helper build/m
      ) do
        described_class.notarize_helper
      end

      expect(described_class::Operations).not_to have_received(:create_zip)
      expect(described_class::Operations).not_to have_received(:submit_for_notarization)
    end

    it 'aborts before notarization work when codesign reports an ad-hoc signature on stderr' do
      allow(Open3).to receive(:capture3).with('codesign', '-dv', bundle_path).and_return(
        ['', "Executable=#{bundle_path}/Contents/MacOS/wifiwand-helper\nSignature=adhoc\n", codesign_status]
      )
      allow(described_class::Operations).to receive(:create_zip)
      allow(described_class::Operations).to receive(:submit_for_notarization)

      expect_system_exit_with_stderr(
        %r{
          Helper\ is\ ad-hoc\ signed.*
          Rebuild\ it\ with\ your\ configured\ Developer\ ID\ identity:.*
          Run:\ bin/mac-helper\ build
        }mx
      ) do
        described_class.notarize_helper
      end

      expect(described_class::Operations).not_to have_received(:create_zip)
      expect(described_class::Operations).not_to have_received(:submit_for_notarization)
    end

    it 'continues into notarization when codesign reports a Developer ID signature' do
      allow(Open3).to receive(:capture3).with('codesign', '-dv', bundle_path).and_return(
        ['', developer_id_signature, codesign_status]
      )
      allow(described_class::Operations).to receive(:create_zip).with(bundle_path, zip_path)
      allow(described_class::Operations).to receive(:submit_for_notarization).with(
        zip_path,
        creds[:profile_name],
        creds[:keychain_path],
        creds[:team_id]
      ).and_return("id: 123\nstatus: Accepted\n")
      allow(described_class::Operations).to receive(:staple_ticket).with(bundle_path)
      allow(FileUtils).to receive(:rm_f).with(zip_path)

      expect { described_class.notarize_helper }
        .to output(/Notarizing helper for distribution.*Notarization successful!/m).to_stdout
    end
  end
end
