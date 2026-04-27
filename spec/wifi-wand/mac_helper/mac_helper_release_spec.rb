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
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }

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
      expect(Open3).to receive(:capture3).with(
        'xcrun', 'notarytool', 'history', '--keychain-profile', 'wifiwand-notarytool'
      ).and_return(['', '', success_status])

      described_class::Operations.run_notarytool(
        ['history'],
        profile_name:    'wifiwand-notarytool',
        keychain_path:   nil,
        team_id:         'TEAM123',
        failure_message: 'Unable to fetch notarization history.'
      )
    end

    it 'includes the custom keychain path when one is configured' do
      expect(Open3).to receive(:capture3).with(
        'xcrun', 'notarytool', 'history', '--keychain-profile', 'wifiwand-notarytool',
        '--keychain', '/tmp/wifiwand.keychain-db'
      ).and_return(['ok', '', success_status])

      described_class::Operations.run_notarytool(
        ['history'],
        profile_name:    'wifiwand-notarytool',
        keychain_path:   '/tmp/wifiwand.keychain-db',
        team_id:         'TEAM123',
        failure_message: 'Unable to fetch notarization history.'
      )
    end

    it 'prints command output unless output suppression is requested' do
      allow(Open3).to receive(:capture3).and_return(["submitted\n", "warning\n", success_status])

      expect do
        described_class::Operations.run_notarytool(
          ['history'],
          profile_name:    'wifiwand-notarytool',
          keychain_path:   nil,
          team_id:         'TEAM123',
          failure_message: 'Unable to fetch notarization history.'
        )
      end.to output(/submitted.*warning/m).to_stdout
    end

    it 'explains how to restore the keychain profile when notarytool cannot load it' do
      allow(Open3).to receive(:capture3).and_return(
        ['', 'No Keychain password item found for profile', failure_status]
      )

      expect_system_exit_with_stderr(/Create or refresh it with:.*store-credentials wifiwand-notarytool/m) do
        described_class::Operations.run_notarytool(
          ['history'],
          profile_name:    'wifiwand-notarytool',
          keychain_path:   nil,
          team_id:         'TEAM123',
          failure_message: 'Unable to fetch notarization history.'
        )
      end
    end

    it 'aborts with the provided failure message for generic notarytool failures' do
      allow(Open3).to receive(:capture3).and_return(['', 'network down', failure_status])

      expect_system_exit_with_stderr(/Unable to fetch notarization history\./) do
        described_class::Operations.run_notarytool(
          ['history'],
          profile_name:    'wifiwand-notarytool',
          keychain_path:   nil,
          team_id:         'TEAM123',
          failure_message: 'Unable to fetch notarization history.'
        )
      end
    end
  end

  describe '.verify_source_attestation!' do
    it 'confirms the bundle matches the checked-in Swift sources' do
      allow(WifiWand::MacOsWifiAuthHelper).to receive(:verify_source_bundle_current!)

      expect { described_class.verify_source_attestation! }
        .to output(/Source attestation matches committed Swift source and bundle/).to_stdout
    end

    it 'aborts with the attestation failure reason when verification raises' do
      allow(WifiWand::MacOsWifiAuthHelper).to receive(:verify_source_bundle_current!)
        .and_raise(StandardError, 'manifest digest mismatch')

      expect_system_exit_with_stderr(/Source attestation failed:.*manifest digest mismatch/m) do
        described_class.verify_source_attestation!
      end
    end
  end

  describe '.build_signed_helper' do
    let(:helper) { WifiWand::MacOsWifiAuthHelper }
    let(:source_path) { '/tmp/WifiNetworkConnector.swift' }
    let(:bundle_path) { '/tmp/wifiwand-helper.app' }
    let(:destination_path) { "#{bundle_path}/Contents/MacOS/#{helper::EXECUTABLE_NAME}" }

    before do
      allow(described_class::Operations).to receive(:require_macos!)
      allow(described_class::Operations).to receive(:verify_identity_configured)
      allow(described_class::Operations).to receive(:verify_identity_exists)
      allow(described_class::Operations).to receive(:verify_universal_binary).and_return(true)
      allow(described_class).to receive(:verify_source_attestation!)
      allow(helper).to receive_messages(
        source_swift_path:  source_path,
        source_bundle_path: bundle_path
      )
      allow(helper).to receive(:compile_helper)
      allow(helper).to receive(:write_source_bundle_manifest)
    end

    around do |example|
      original_identity = ENV['WIFIWAND_CODESIGN_IDENTITY']
      ENV.delete('WIFIWAND_CODESIGN_IDENTITY')
      example.run
    ensure
      ENV['WIFIWAND_CODESIGN_IDENTITY'] = original_identity
    end

    it 'builds the helper, writes the manifest, verifies attestation, and exposes the signing identity' do
      expect(helper).to receive(:compile_helper).with(
        source_path, destination_path, hash_including(:out_stream)
      )
      expect(helper).to receive(:write_source_bundle_manifest).ordered
      expect(described_class::Operations).to receive(:verify_universal_binary).with(destination_path).ordered
      expect(described_class).to receive(:verify_source_attestation!).ordered

      expect { described_class.build_signed_helper }
        .to output(/Building helper for distribution.*Helper built and signed successfully!/m).to_stdout

      expect(ENV['WIFIWAND_CODESIGN_IDENTITY']).to eq(described_class::CODESIGN_IDENTITY)
    end

    it 'still verifies attestation and prints next steps when the binary is not universal' do
      allow(described_class::Operations).to receive(:verify_universal_binary).and_return(false)

      expect(described_class).to receive(:verify_source_attestation!)

      expect { described_class.build_signed_helper }
        .to output(/Verifying binary architectures.*Helper built and signed successfully!/m).to_stdout
    end
  end

  describe '.test_signed_helper' do
    let(:helper) { WifiWand::MacOsWifiAuthHelper }
    let(:bundle_path) { '/tmp/wifiwand-helper.app' }
    let(:executable_path) { "#{bundle_path}/Contents/MacOS/#{helper::EXECUTABLE_NAME}" }

    before do
      allow(described_class::Operations).to receive(:require_macos!)
      allow(described_class).to receive(:verify_source_attestation!)
      allow(helper).to receive(:source_bundle_path).and_return(bundle_path)
      allow(described_class::Operations).to receive(:helper_executable_path).and_return(executable_path)
    end

    it 'aborts when the built helper executable is missing' do
      allow(File).to receive(:exist?).with(executable_path).and_return(false)

      expect_system_exit_with_stderr(/Helper not found at .* Run: bin\/mac-helper build/) do
        described_class.test_signed_helper
      end
    end

    it 'prints signature details, architectures, and runs the signed helper smoke test' do
      allow(File).to receive(:exist?).with(executable_path).and_return(true)
      allow(described_class).to receive(:system).with('codesign', '-dvv', bundle_path)
      allow(described_class::Operations).to receive(:get_binary_architectures).with(executable_path)
        .and_return(%w[arm64 x86_64])
      allow(described_class::Operations).to receive(:verify_signature).with(bundle_path)
      allow(described_class::Operations).to receive(:test_helper_execution).with(executable_path)

      expect { described_class.test_signed_helper }
        .to output(/Testing signed helper.*Binary architectures:.*arm64, x86_64/m).to_stdout
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
        ['', developer_id_signature, success_status]
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

    it 'aborts when Apple does not accept the notarization submission' do
      allow(Open3).to receive(:capture3).with('codesign', '-dv', bundle_path).and_return(
        ['', developer_id_signature, success_status]
      )
      allow(described_class::Operations).to receive(:create_zip).with(bundle_path, zip_path)
      allow(described_class::Operations).to receive(:submit_for_notarization)
        .and_return("id: 123\nstatus: Invalid\n")
      allow(described_class::Operations).to receive(:staple_ticket)
      allow(FileUtils).to receive(:rm_f)

      expect_system_exit_with_stderr(/Notarization was rejected\. Check the output above for details\./) do
        described_class.notarize_helper
      end

      expect(described_class::Operations).not_to have_received(:staple_ticket)
      expect(FileUtils).not_to have_received(:rm_f)
    end
  end

  describe '.notarization_status' do
    before do
      allow(described_class).to receive(:fetch_notary_credentials!).and_return(creds)
    end

    it 'rejects a missing submission ID' do
      expect_system_exit_with_stderr(/Submission ID is required/) do
        described_class.notarization_status(nil)
      end
    end

    it 'requests the selected submission status from notarytool' do
      expect(described_class::Operations).to receive(:run_notarytool).with(
        %w[info sub-123],
        **creds,
        failure_message: 'Unable to fetch notarization status. Check the submission ID and try again.'
      )

      expect { described_class.notarization_status('sub-123') }
        .to output(/Status for submission sub-123:/).to_stdout
    end
  end

  describe '.notarization_log' do
    before do
      allow(described_class).to receive(:fetch_notary_credentials!).and_return(creds)
    end

    it 'rejects a missing submission ID' do
      expect_system_exit_with_stderr(/Submission ID is required/) do
        described_class.notarization_log('')
      end
    end

    it 'requests the selected submission log from notarytool' do
      expect(described_class::Operations).to receive(:run_notarytool).with(
        %w[log sub-456],
        **creds,
        failure_message: 'Unable to fetch notarization log. Check the submission ID and try again.'
      )

      expect { described_class.notarization_log('sub-456') }
        .to output(/Log for submission sub-456:/).to_stdout
    end
  end

  describe '.notarization_history_entries_with_credentials' do
    it 'warns and returns nil when notarytool history is not valid JSON' do
      allow(described_class::Operations).to receive(:run_notarytool).and_return('not-json')

      expect do
        expect(described_class.notarization_history_entries_with_credentials(creds)).to be_nil
      end.to output(/unable to parse notarytool history JSON/i).to_stderr
    end
  end

  describe '.select_submission_id' do
    let(:history_entries) do
      [
        { 'id' => 'latest-001', 'status' => 'Accepted' },
        { 'id' => 'pending-001', 'status' => described_class::PENDING_NOTARIZATION_STATUS },
        { 'id' => 'oldest-001', 'status' => 'Invalid' },
      ]
    end

    before do
      allow(described_class).to receive(:notarization_history_entries).and_return(history_entries)
    end

    it 'returns the oldest submission when ascending order is requested' do
      expect(described_class.select_submission_id(order: :asc)).to eq('oldest-001')
    end

    it 'filters to pending submissions before selecting an ID' do
      expect(described_class.select_submission_id(order: :desc, pending_only: true)).to eq('pending-001')
    end

    it 'returns nil when the filtered history is empty' do
      allow(described_class).to receive(:notarization_history_entries).and_return([])

      expect(described_class.select_submission_id(order: :desc)).to be_nil
    end
  end

  describe '.normalize_submission_order' do
    it 'normalizes supported order aliases' do
      expect(described_class.normalize_submission_order(:ascending)).to eq(:asc)
      expect(described_class.normalize_submission_order(:descending)).to eq(:desc)
    end

    it 'raises for unsupported values' do
      expect { described_class.normalize_submission_order(:sideways) }
        .to raise_error(ArgumentError, /Invalid order: :sideways/)
    end
  end

  describe '.release_helper' do
    it 'runs build, test, and notarize in order and prints workflow separators' do
      expect(described_class).to receive(:build_signed_helper).ordered
      expect(described_class).to receive(:test_signed_helper).ordered
      expect(described_class).to receive(:notarize_helper).ordered

      expect { described_class.release_helper }
        .to output(
          /Starting complete helper release workflow.*Complete release workflow finished!/m
        ).to_stdout
    end
  end

  describe '.codesign_status' do
    let(:helper) { WifiWand::MacOsWifiAuthHelper }
    let(:bundle_path) { '/tmp/wifiwand-helper.app' }
    let(:executable_path) { "#{bundle_path}/Contents/MacOS/#{helper::EXECUTABLE_NAME}" }

    before do
      allow(described_class::Operations).to receive(:require_macos!)
      allow(helper).to receive(:source_bundle_path).and_return(bundle_path)
      allow(described_class::Operations).to receive(:helper_executable_path).and_return(executable_path)
    end

    it 'prints the missing bundle guidance and exits when no helper has been built' do
      allow(File).to receive(:exist?).with(bundle_path).and_return(false)

      expect do
        expect { described_class.codesign_status }.to raise_error(SystemExit)
      end.to output(
        /Helper bundle not found at #{Regexp.escape(bundle_path)}.*Run: bin\/mac-helper build/m
      ).to_stdout
    end

    it 'reports invalid signatures and missing notarization for non-universal helpers' do
      allow(File).to receive(:exist?).with(bundle_path).and_return(true)
      allow(described_class).to receive(:verify_source_attestation!)
      allow(described_class).to receive(:system).with('codesign', '-dvv', bundle_path)
      allow(described_class::Operations).to receive(:get_binary_architectures).with(executable_path)
        .and_return(['x86_64'])
      allow(Open3).to receive(:capture3).with('codesign', '--verify', '--verbose', bundle_path).and_return(
        ['', 'invalid signature data', failure_status]
      )
      allow(Open3).to receive(:capture3).with('spctl', '-a', '-vv', '-t', 'install', bundle_path).and_return(
        ['rejected', '', failure_status]
      )

      expect { described_class.codesign_status }
        .to output(
          /Not universal: x86_64.*Signature is invalid:.*invalid signature data.*not notarized/m
        ).to_stdout
    end

    it 'recognizes notarized Developer ID output even when spctl exits non-zero' do
      allow(File).to receive(:exist?).with(bundle_path).and_return(true)
      allow(described_class).to receive(:verify_source_attestation!)
      allow(described_class).to receive(:system).with('codesign', '-dvv', bundle_path)
      allow(described_class::Operations).to receive(:get_binary_architectures).with(executable_path)
        .and_return(%w[arm64 x86_64])
      allow(Open3).to receive(:capture3).with('codesign', '--verify', '--verbose', bundle_path).and_return(
        ['', '', success_status]
      )
      allow(Open3).to receive(:capture3).with('spctl', '-a', '-vv', '-t', 'install', bundle_path).and_return(
        ["source=Notarized Developer ID\n", '', failure_status]
      )

      expect { described_class.codesign_status }
        .to output(/Universal binary.*Signature is valid.*Helper is notarized/m).to_stdout
    end
  end

  describe '.staple_ticket' do
    it 'prints a warning instead of aborting when ticket stapling fails' do
      allow(Open3).to receive(:capture3).with('xcrun', 'stapler', 'staple', '/tmp/helper.app').and_return(
        ['', 'ticket missing', failure_status]
      )

      expect { described_class::Operations.staple_ticket('/tmp/helper.app') }
        .to output(/Could not staple ticket.*ticket missing/m).to_stdout
    end
  end
end
