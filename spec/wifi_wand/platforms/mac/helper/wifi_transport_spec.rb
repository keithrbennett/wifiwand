# frozen_string_literal: true

require_relative '../../../../spec_helper'
require_relative '../../../../../lib/wifi_wand/platforms/mac/helper/wifi_transport'

module WifiWand
  describe Platforms::Mac::Helper::WifiTransport do
    let(:out_stream) { StringIO.new }
    let(:err_stream) { StringIO.new }
    let(:verbose) { true }
    let(:swift_runtime) { instance_double(WifiWand::Platforms::Mac::Helper::SwiftRuntime) }
    let(:command_runner) { double('command_runner') }
    let(:wifi_interface_provider) { -> { 'en0' } }
    let(:transport) do
      described_class.new(
        swift_runtime:           swift_runtime,
        command_runner:          command_runner,
        wifi_interface_provider: wifi_interface_provider,
        out_stream_provider:     -> { out_stream },
        err_stream_provider:     -> { err_stream },
        verbosity_provider:      -> { verbose }
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

        expect(err_stream.string).to include(
          "Swift/CoreWLAN failed (#{error_text}). Trying networksetup fallback..."
        )
      end

      it 'falls back to networksetup for recoverable Swift network-not-found failures' do
        error_text = 'Error: Network not found'

        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
          .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
        expect(swift_runtime).to receive(:fallback_connect_error?).with(error_text).and_return(true)
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'password'])
          .and_return(command_result(stdout: ''))

        transport.connect('TestNetwork', 'password')

        expect(err_stream.string).to include(
          "Swift/CoreWLAN failed (#{error_text}). Trying networksetup fallback..."
        )
      end

      it 'logs and re-raises unexpected Swift connect failures' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
          .and_raise(StandardError.new('swift exploded'))
        expect(swift_runtime).not_to receive(:fallback_connect_error?)
        expect(command_runner).not_to receive(:call)

        expect { transport.connect('TestNetwork', 'password') }
          .to raise_error(StandardError, 'swift exploded')

        expect(err_stream.string).to include(
          'Unexpected Swift/CoreWLAN connect error: StandardError: swift exploded'
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

      {
        'invalid password'       => 'Error: Invalid password',
        'authentication failure' => 'Error: Authentication failed - might require captive portal login',
      }.each do |description, error_text|
        it "raises NetworkAuthenticationError for Swift #{description} output" do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
            .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
          expect(swift_runtime).not_to receive(:fallback_connect_error?)
          expect(command_runner).not_to receive(:call)

          expect { transport.connect('TestNetwork', 'password') }
            .to raise_error(WifiWand::NetworkAuthenticationError) do |error|
              expect(error.network_name).to eq('TestNetwork')
              expect(error.reason).to eq(error_text)
            end
        end
      end

      [
        ['timeout', 'Error: Connection timeout', 'Error: Connection timeout'],
        [
          'timed out',
          'Error: Connection attempt timed out',
          'Error: Connection attempt timed out',
        ],
        [
          'out of range',
          "Failed to join network TestNetwork.\nNetwork moved out of range.",
          'Network moved out of range.',
        ],
        [
          'Swift join header with detail',
          "Error: Failed to join TestNetwork.\nNetwork moved out of range.",
          'Network moved out of range.',
        ],
        ['unreachable', 'Error: Network unreachable', 'Error: Network unreachable'],
      ].each do |description, error_text, expected_reason|
        it "raises NetworkConnectionError for Swift #{description} output" do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
          allow(swift_runtime).to receive(:connect).with('TestNetwork', 'password')
            .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: error_text))
          expect(swift_runtime).to receive(:fallback_connect_error?).with(error_text).and_return(false)
          expect(command_runner).not_to receive(:call)

          expect { transport.connect('TestNetwork', 'password') }
            .to raise_error(WifiWand::NetworkConnectionError) do |error|
              expect(error.network_name).to eq('TestNetwork')
              expect(error.reason).to eq(expected_reason)
              expect(error.source).to eq(:swift)
            end
        end
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

      it 'preserves WiFi interface lookup command errors before networksetup connect runs' do
        interface_error = os_command_error(
          exitstatus: 1,
          command:    'networksetup -listallhardwareports',
          text:       'No WiFi interface found'
        )
        failing_transport = described_class.new(
          swift_runtime:           swift_runtime,
          command_runner:          command_runner,
          wifi_interface_provider: -> { raise interface_error },
          out_stream_provider:     -> { out_stream },
          err_stream_provider:     -> { err_stream },
          verbosity_provider:      -> { verbose }
        )
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).not_to receive(:call)

        expect { failing_transport.connect('TestNetwork') }
          .to raise_error(WifiWand::CommandExecutor::OsCommandError, /No WiFi interface found/)
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

      {
        'incorrect password'           => 'The password for this network is incorrect.',
        'authentication timeout'       => 'Authentication timed out while joining.',
        '802.1x authentication failed' => '802.1x authentication failed.',
        'password required'            => 'Password required for this network.',
      }.each do |description, reason|
        it "raises NetworkAuthenticationError for #{description} output" do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
          failure_output = "Failed to join network TestNetwork.\n#{reason}"
          expect(command_runner).to receive(:call)
            .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'badpass'])
            .and_return(command_result(stdout: failure_output))

          expect { transport.connect('TestNetwork', 'badpass') }
            .to raise_error(WifiWand::NetworkAuthenticationError, /#{Regexp.escape(reason)}/)
        end
      end

      it 'raises NetworkAuthenticationError when networksetup exits non-zero for an auth failure' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        failure_output = 'Error: Invalid password'
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'badpass'])
          .and_raise(os_command_error(exitstatus: 1, command: 'networksetup', text: failure_output))

        expect { transport.connect('TestNetwork', 'badpass') }
          .to raise_error(WifiWand::NetworkAuthenticationError) do |error|
            expect(error.network_name).to eq('TestNetwork')
            expect(error.reason).to eq(failure_output)
          end
      end

      it 'preserves networksetup output as the reason when no detail line is available' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        failure_output = 'Failed to join network TestNetwork: invalid password'
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork', 'badpass'])
          .and_return(command_result(stdout: failure_output))

        expect { transport.connect('TestNetwork', 'badpass') }
          .to raise_error(WifiWand::NetworkAuthenticationError, /#{Regexp.escape(failure_output)}/)
      end

      [
        ['network not found', 'Could not find network TestNetwork.', 'Could not find network TestNetwork.'],
        ['CoreWLAN numeric failure', 'Error: -3900', 'Error: -3900'],
        ['generic connect failure', 'Could not connect to the network.', 'Could not connect to the network.'],
        [
          'generic header with detail',
          "Failed to join network TestNetwork.\nNetwork moved out of range.",
          'Network moved out of range.',
        ],
      ].each do |description, failure_output, expected_reason|
        it "raises NetworkConnectionError when networksetup reports #{description}" do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
          expect(command_runner).to receive(:call)
            .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork'])
            .and_return(command_result(stdout: failure_output))

          expect { transport.connect('TestNetwork') }
            .to raise_error(WifiWand::NetworkConnectionError) do |error|
              expect(error.network_name).to eq('TestNetwork')
              expect(error.reason).to eq(expected_reason)
              expect(error.source).to eq(:networksetup)
            end
        end
      end

      it 'raises NetworkConnectionError when networksetup exits non-zero for a connect failure' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        failure_output = 'Could not connect to the network.'
        expect(command_runner).to receive(:call)
          .with(['networksetup', '-setairportnetwork', 'en0', 'TestNetwork'])
          .and_raise(os_command_error(exitstatus: 1, command: 'networksetup', text: failure_output))

        expect { transport.connect('TestNetwork') }
          .to raise_error(WifiWand::NetworkConnectionError) do |error|
            expect(error.network_name).to eq('TestNetwork')
            expect(error.reason).to eq(failure_output)
            expect(error.source).to eq(:networksetup)
          end
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

          expect(err_stream.string).to eq('')
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

      it 'falls back to ifconfig after an expected Swift disconnect failure' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:disconnect)
          .and_raise(WifiWand::CommandTimeoutError.new(command: 'swift disconnect', timeout_in_secs: 1))
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).not_to receive(:call).with(%w[ifconfig en0 disassociate],
          raise_on_error: false)

        expect(transport.disconnect).to be_nil
        expect(err_stream.string).to include(
          'Swift/CoreWLAN disconnect failed: Command timed out after 1 seconds: swift disconnect. ' \
            'Falling back to ifconfig...'
        )
      end

      it 'logs and re-raises unexpected Swift disconnect failures' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(true)
        allow(swift_runtime).to receive(:disconnect).and_raise(StandardError.new('swift failed'))
        expect(command_runner).not_to receive(:call)

        expect { transport.disconnect }.to raise_error(StandardError, 'swift failed')
        expect(err_stream.string).to include(
          'Unexpected Swift/CoreWLAN disconnect error: StandardError: swift failed'
        )
      end

      it 'uses plain ifconfig when sudo ifconfig fails' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stderr: 'sudo requires a password', exitstatus: 1,
          command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).to receive(:call).with(%w[ifconfig en0 disassociate],
          raise_on_error: false)
          .and_return(command_result(stdout: '', command: 'ifconfig en0 disassociate'))

        expect(transport.disconnect).to be_nil
      end

      it 'raises a disconnect error when both ifconfig fallback attempts fail' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stderr: 'sudo authentication failed', exitstatus: 1,
          command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).to receive(:call).with(%w[ifconfig en0 disassociate],
          raise_on_error: false)
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

      it 'raises a disconnect error with command status when ifconfig failures have no output' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(exitstatus: 1, command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).to receive(:call).with(%w[ifconfig en0 disassociate],
          raise_on_error: false)
          .and_return(command_result(exitstatus: 1, command: 'ifconfig en0 disassociate'))

        expect { transport.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
          expect(error.reason).to include('sudo ifconfig en0 disassociate exited with status 1')
          expect(error.reason).to include('ifconfig en0 disassociate exited with status 1')
        end
      end

      it 'raises a disconnect error when sudo ifconfig times out' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_raise(WifiWand::CommandTimeoutError.new(
          command:         'sudo ifconfig en0 disassociate',
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ))

        expect { transport.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
          expect(error.network_name).to be_nil
          expect(error.reason).to include('Command timed out')
          expect(error.reason).to include('sudo ifconfig en0 disassociate')
        end
      end

      it 'raises a disconnect error when plain ifconfig cannot be started' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stderr: 'sudo requires a password', exitstatus: 1,
          command: 'sudo ifconfig en0 disassociate'))
        expect(command_runner).to receive(:call).with(%w[ifconfig en0 disassociate],
          raise_on_error: false)
          .and_raise(WifiWand::CommandSpawnError.new(
            command: 'ifconfig en0 disassociate',
            reason:  'Resource temporarily unavailable'
          ))

        expect { transport.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
          expect(error.network_name).to be_nil
          expect(error.reason).to include('ifconfig en0 disassociate')
          expect(error.reason).to include('Resource temporarily unavailable')
        end
      end

      it 'uses ifconfig when Swift/CoreWLAN is unavailable and logs that fallback' do
        allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
        expect(command_runner).to receive(:call).with(
          %w[sudo ifconfig en0 disassociate],
          raise_on_error:  false,
          timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))

        expect(transport.disconnect).to be_nil
        expect(err_stream.string).to include('Swift/CoreWLAN not available. Using ifconfig...')
      end

      context 'when verbose logging is disabled' do
        let(:verbose) { false }

        it 'suppresses disconnect fallback messaging' do
          allow(swift_runtime).to receive(:swift_and_corewlan_present?).and_return(false)
          expect(command_runner).to receive(:call).with(
            %w[sudo ifconfig en0 disassociate],
            raise_on_error:  false,
            timeout_in_secs: described_class::SUDO_IFCONFIG_TIMEOUT_SECONDS
          ).and_return(command_result(stdout: '', command: 'sudo ifconfig en0 disassociate'))

          expect(transport.disconnect).to be_nil
          expect(err_stream.string).to eq('')
        end
      end
    end
  end
end
