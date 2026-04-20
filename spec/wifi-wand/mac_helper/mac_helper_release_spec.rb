# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/mac_helper/mac_helper_release'

RSpec.describe WifiWand::MacHelperRelease do
  let(:creds) do
    {
      apple_id:       'dev@example.com',
      apple_password: 'app-password',
      team_id:        'TEAM123',
    }
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

      expect do
        expect { described_class.cancel_notarization('accepted-001') }.to raise_error(SystemExit)
      end.to output(/Submission accepted-001 is Accepted and cannot be canceled/).to_stderr
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

      expect do
        expect { described_class.cancel_notarization('explicit-001') }.to raise_error(SystemExit)
      end.to output(/Submission explicit-001 is Invalid and cannot be canceled/).to_stderr
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

      expect do
        expect { described_class.cancel_notarization('missing-001') }.to raise_error(SystemExit)
      end.to output(
        /Submission missing-001 was not found in notarization history.*Run: bin\/mac-helper history/m
      ).to_stderr
    end
  end
end
