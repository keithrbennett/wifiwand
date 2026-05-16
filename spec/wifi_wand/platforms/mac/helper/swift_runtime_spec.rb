# frozen_string_literal: true

require_relative '../../../../spec_helper'
require_relative '../../../../../lib/wifi_wand/platforms/mac/helper/swift_runtime'

module WifiWand
  describe Platforms::Mac::Helper::SwiftRuntime do
    let(:out_stream) { StringIO.new }
    let(:verbose) { true }
    let(:command_runner) { instance_double(Proc) }
    let(:runtime) do
      described_class.new(
        command_runner:      command_runner,
        out_stream_provider: -> { out_stream },
        verbosity_provider:  -> { verbose }
      )
    end

    describe '#swift_and_corewlan_present?' do
      it 'probes Swift/CoreWLAN availability once and memoizes the result' do
        expect(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false).once
          .and_return(command_result(stdout: ''))

        2.times do
          expect(runtime.swift_and_corewlan_present?).to be(true)
        end
      end

      it 'passes an explicit timeout into the Swift/CoreWLAN probe' do
        expect(command_runner).to receive(:call).with(
          ['swift', '-e', 'import CoreWLAN'],
          raise_on_error:  false,
          timeout_in_secs: 0.25
        ).and_return(command_result(stdout: ''))

        expect(runtime.swift_and_corewlan_present?(timeout_in_secs: 0.25)).to be(true)
      end

      it 'does not memoize a bounded Swift/CoreWLAN probe timeout' do
        expect(command_runner).to receive(:call).with(
          ['swift', '-e', 'import CoreWLAN'],
          raise_on_error:  false,
          timeout_in_secs: 0.25
        ).and_raise(
          WifiWand::CommandTimeoutError.new(command: 'swift -e import CoreWLAN', timeout_in_secs: 0.25)
        )
        expect(command_runner).to receive(:call).with(
          ['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false
        ).and_return(command_result(stdout: ''))

        expect(runtime.swift_and_corewlan_present?(timeout_in_secs: 0.25)).to be(false)
        expect(runtime.swift_and_corewlan_present?).to be(true)
      end

      it 'returns false and does not memoize when the Swift/CoreWLAN probe cannot start' do
        expect(command_runner).to receive(:call).with(
          ['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false
        ).and_raise(
          WifiWand::CommandSpawnError.new(
            command: 'swift -e import CoreWLAN',
            reason:  'resource temporarily unavailable'
          )
        )
        expect(command_runner).to receive(:call).with(
          ['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false
        ).and_return(command_result(stdout: ''))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(runtime.swift_and_corewlan_present?).to be(true)
        expect(out_stream.string).to include('Swift/CoreWLAN check could not start')
      end

      it 'returns false for returned Swift/CoreWLAN probe failures and memoizes the result' do
        expect(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false).once
          .and_return(command_result(stderr: 'toolchain mismatch', exitstatus: 2, command: 'swift'))

        2.times do
          expect(runtime.swift_and_corewlan_present?).to be(false)
        end
      end

      it 'returns false when the command runner reports Swift is not installed' do
        expect(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(WifiWand::CommandNotFoundError.new('swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
      end

      it 'logs a targeted message when the command runner reports Swift is not installed' do
        expect(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(WifiWand::CommandNotFoundError.new('swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift command not found. Install Xcode Command Line Tools.')
      end

      it 'logs a targeted message for legacy exit-code command-not-found failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_return(command_result(exitstatus: 127, command: 'swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include(
          'Swift command not found (exit code 127). Install Xcode Command Line Tools.'
        )
      end

      it 'logs a targeted message when CoreWLAN is unavailable and the probe returns a failure' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_return(command_result(stderr: 'missing framework', exitstatus: 1, command: 'swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('CoreWLAN framework not available (exit code 1)')
      end

      it 'logs the command output for returned toolchain probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_return(command_result(stderr: 'toolchain mismatch', exitstatus: 2, command: 'swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift/CoreWLAN check failed with exit code 2')
        expect(out_stream.string).to include('toolchain mismatch')
      end

      it 'logs the command output for returned unknown probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_return(command_result(stderr: 'unexpected compiler output', exitstatus: 66, command: 'swift'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift/CoreWLAN check failed with exit code 66')
        expect(out_stream.string).to include('unexpected compiler output')
      end

      it 'logs a targeted message when a raised command error reports CoreWLAN is unavailable' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: 'missing framework'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('CoreWLAN framework not available (exit code 1)')
      end

      it 'logs a targeted message when a raised command error reports legacy command-not-found status' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(os_command_error(exitstatus: 127, command: 'swift', text: ''))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include(
          'Swift command not found (exit code 127). Install Xcode Command Line Tools.'
        )
      end

      it 'logs the command output for other raised command probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(os_command_error(exitstatus: 2, command: 'swift', text: 'toolchain mismatch'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift/CoreWLAN check failed with exit code 2')
        expect(out_stream.string).to include('toolchain mismatch')
      end

      it 'logs and re-raises non-command probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
          raise_on_error: false)
          .and_raise(StandardError.new('unexpected'))

        expect { runtime.swift_and_corewlan_present? }.to raise_error(StandardError, 'unexpected')
        expect(out_stream.string).to include(
          'Unexpected error checking Swift/CoreWLAN: StandardError: unexpected'
        )
      end

      context 'when verbose logging is disabled' do
        let(:verbose) { false }

        it 'suppresses returned Swift/CoreWLAN probe failure messages' do
          allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
            raise_on_error: false)
            .and_return(command_result(stderr: 'toolchain mismatch', exitstatus: 2, command: 'swift'))

          expect(runtime.swift_and_corewlan_present?).to be(false)
          expect(out_stream.string).to eq('')
        end

        it 'suppresses raised Swift/CoreWLAN probe failure messages' do
          allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
            raise_on_error: false)
            .and_raise(os_command_error(exitstatus: 2, command: 'swift', text: 'toolchain mismatch'))

          expect(runtime.swift_and_corewlan_present?).to be(false)
          expect(out_stream.string).to eq('')
        end

        it 'suppresses timeout probe messages' do
          allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'],
            raise_on_error: false)
            .and_raise(WifiWand::CommandTimeoutError.new(command: 'swift', timeout_in_secs: 5))

          expect(runtime.swift_and_corewlan_present?).to be(false)
          expect(out_stream.string).to eq('')
        end
      end
    end

    describe '#run_swift_command' do
      it 'constructs and executes the expected Swift source command' do
        expect(command_runner).to receive(:call) do |cmd|
          expect(cmd[0]).to eq('swift')
          expect(cmd[1]).to end_with('WifiNetworkConnector.swift')
          expect(cmd[2]).to eq('TestNetwork')
          expect(cmd[3]).to eq('password123')
        end

        runtime.run_swift_command('WifiNetworkConnector', 'TestNetwork', 'password123')
      end
    end

    describe '#connect' do
      it 'dispatches to the connector script with a password when provided' do
        expect(runtime).to receive(:run_swift_command)
          .with('WifiNetworkConnector', 'TestNetwork', 'password123')

        runtime.connect('TestNetwork', 'password123')
      end

      it 'dispatches to the connector script without a password when absent' do
        expect(runtime).to receive(:run_swift_command).with('WifiNetworkConnector', 'TestNetwork')

        runtime.connect('TestNetwork')
      end
    end

    describe '#disconnect' do
      it 'dispatches to the disconnector script' do
        expect(runtime).to receive(:run_swift_command).with('WifiNetworkDisconnector')

        runtime.disconnect
      end
    end

    describe '#fallback_connect_error?' do
      [
        'Error connecting to network (code: -3900)',
        'Error connecting to network (code: -3905)',
        'CoreWLAN generic error',
        'Possible keychain access or authentication issue',
        'Network not found',
        'The operation could not be completed. tmpErr (code: 82)',
        "The operation couldn't be completed. tmpErr (code: 82)",
        'The operation couldn???t be completed because tmpErr occurred',
      ].each do |error_text|
        it "recognizes recoverable Swift/CoreWLAN connect failure: #{error_text}" do
          expect(runtime.fallback_connect_error?(error_text)).to be(true)
        end
      end

      it 'treats nil error text as non-recoverable' do
        expect(runtime.fallback_connect_error?(nil)).to be(false)
      end

      it 'returns false for non-recoverable connect failures' do
        expect(runtime.fallback_connect_error?('permission denied')).to be(false)
      end
    end
  end
end
