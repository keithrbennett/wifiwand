# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/mac_helper/mac_os_wifi_transport'

module WifiWand
  describe MacOsWifiTransport do
    let(:out_stream) { StringIO.new }
    let(:verbose) { true }
    let(:swift_runtime) { instance_double(WifiWand::MacOsSwiftRuntime) }
    let(:command_runner) { double('command_runner') }
    let(:wifi_interface_proc) { -> { 'en0' } }
    let(:transport) do
      described_class.new(
        swift_runtime:       swift_runtime,
        command_runner:      command_runner,
        wifi_interface_proc: wifi_interface_proc,
        out_stream_proc:     -> { out_stream },
        verbose_proc:        -> { verbose }
      )
    end

    describe '#connect' do
      it 'uses the Swift runtime when CoreWLAN is available and the connect succeeds' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        expect(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
        expect(command_runner).not_to receive(:call)

        transport.connect('TestNetwork', 'password')
      end

      it 'falls back to networksetup for recoverable Swift connect failures' do
        error_text = "Error connecting: The operation couldn't be completed. tmpErr (code: 82)"

        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
          .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
        expect(swift_runtime).to receive(:fallback_connect_error?).with(error_text).and_return(true)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'password'])
          .and_return(command_result(stdout: ''))

        transport.connect('TestNetwork', 'password')

        expect(out_stream.string).to include(
          "Swift/CoreWLAN failed (#{error_text}). Trying networksetup fallback..."
        )
      end

      it 'falls back to networksetup for generic Swift connect failures' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
          .and_raise(StandardError.new('swift exploded'))
        expect(swift_runtime).not_to receive(:fallback_connect_error?)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'password'])
          .and_return(command_result(stdout: ''))

        transport.connect('TestNetwork', 'password')

        expect(out_stream.string).to include(
          'Swift/CoreWLAN failed: swift exploded. Trying networksetup fallback...'
        )
      end

      it 're-raises Swift connect failures that are not fallback candidates' do
        error_text = 'Error connecting: permission denied'

        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
          .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
        expect(swift_runtime).to receive(:fallback_connect_error?).with(error_text).and_return(false)
        expect(command_runner).not_to receive(:call)

        expect do
          transport.connect('TestNetwork', 'password')
        end.to raise_error(WifiWand::CommandExecutor::OsCommandError, /permission denied/)
      end

      it 'uses networksetup directly with a password when Swift/CoreWLAN is unavailable' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'password123'])
          .and_return(command_result(stdout: ''))

        transport.connect('TestNetwork', 'password123')
      end

      it 'uses networksetup directly when Swift/CoreWLAN is unavailable' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork'])
          .and_return(command_result(stdout: ''))

        transport.connect('TestNetwork')
      end

      it 'raises NetworkAuthenticationError with reason when password is invalid' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        failure_output = "Failed to join network TestNetwork.\nReason: Invalid password."
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'badpass'])
          .and_return(command_result(stdout: failure_output))

        error = begin
          transport.connect('TestNetwork', 'badpass')
        rescue WifiWand::NetworkAuthenticationError => e
          e
        end

        expect(error).to be_a(WifiWand::NetworkAuthenticationError)
        expect(error.reason).to eq('Reason: Invalid password.')
        expect(error.message).to include('Invalid password')
      end

      it 'raises OsCommandError when networksetup output reports a non-auth failure' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        failure_output = 'Could not find network TestNetwork.'
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork'])
          .and_return(command_result(stdout: failure_output))

        expect do
          transport.connect('TestNetwork')
        end.to raise_error(WifiWand::CommandExecutor::OsCommandError, /Could not find network/)
      end

      context 'when verbose logging is disabled' do
        let(:verbose) { false }

        it 'suppresses connect fallback messaging' do
          error_text = "Error connecting: The operation couldn't be completed. tmpErr (code: 82)"

          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
            .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
          expect(swift_runtime).to receive(:fallback_connect_error?).with(error_text).and_return(true)
          expect(command_runner).to receive(:call)
            .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'password'])
            .and_return(command_result(stdout: ''))

          transport.connect('TestNetwork', 'password')

          expect(out_stream.string).to eq('')
        end
      end
    end

    describe '#disconnect' do
      it 'returns nil when the Swift runtime disconnect succeeds' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        expect(swift_runtime).to receive(:disconnect)
        expect(command_runner).not_to receive(:call)

        expect(transport.disconnect).to be_nil
      end

      it 'falls back to ifconfig after a Swift disconnect failure' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:disconnect).and_raise(StandardError.new('swift failed'))
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).not_to receive(:call).with(%w[ifconfig en0 disassociate], false)

        expect(transport.disconnect).to be_nil
        expect(out_stream.string).to include(
          'Swift/CoreWLAN disconnect failed: swift failed. Falling back to ifconfig...'
        )
      end

      it 'raises a disconnect error when both ifconfig fallback attempts fail' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stderr: 'sudo authentication failed', exitstatus: 1,
          command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).to receive(:call).with(%w[ifconfig en0 disassociate], false)
          .and_return(command_result(stderr: 'permission denied', exitstatus: 1,
            command: 'ifconfig en0 disassociate'))

        expect { transport.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
          expect(error.network_name).to be_nil
          expect(error.reason).to include('sudo ifconfig en0 disassociate exited with status 1')
          expect(error.reason).to include('sudo authentication failed')
          expect(error.reason).to include('ifconfig en0 disassociate exited with status 1')
          expect(error.reason).to include('permission denied')
        end
      end

      it 'uses ifconfig when Swift/CoreWLAN is unavailable and logs that fallback' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))

        expect(transport.disconnect).to be_nil
        expect(out_stream.string).to include('Swift/CoreWLAN not available. Using ifconfig...')
      end

      context 'when verbose logging is disabled' do
        let(:verbose) { false }

        it 'suppresses disconnect fallback messaging' do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
          expect(command_runner).to receive(:call).with(
            %w[sudo ifconfig en0 disassociate],
            false,
            timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
          ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))

          expect(transport.disconnect).to be_nil
          expect(out_stream.string).to eq('')
        end
      end
    end
  end
end
