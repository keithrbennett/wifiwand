# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/mac_os/keychain_password_reader'

module WifiWand
  describe MacOsKeychainPasswordReader do
    subject(:reader) { described_class.new(command_runner: command_runner) }

    let(:command_runner) { double('command_runner') }

    describe '#password_for' do
      it 'runs the security keychain lookup command with the default timeout' do
        expected_cmd = [
          'security', 'find-generic-password', '-D', 'AirPort network password',
          '-a', 'TestNetwork', '-w'
        ]
        allow(command_runner).to receive(:call).with(
          expected_cmd,
          raise_on_error:  true,
          timeout_in_secs: described_class::DEFAULT_LOOKUP_TIMEOUT_SECONDS
        ).and_return(command_result(stdout: "mypassword123\n"))

        expect(reader.password_for('TestNetwork')).to eq('mypassword123')
      end

      it 'allows callers to request an explicit lookup timeout' do
        expected_cmd = [
          'security', 'find-generic-password', '-D', 'AirPort network password',
          '-a', 'TestNetwork', '-w'
        ]
        allow(command_runner).to receive(:call).with(
          expected_cmd,
          raise_on_error:  true,
          timeout_in_secs: 1.5
        ).and_return(command_result(stdout: "mypassword123\n"))

        expect(reader.password_for('TestNetwork', timeout_in_secs: 1.5)).to eq('mypassword123')
      end

      it 'returns nil when the keychain item is missing' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 44, command: 'security', text: ''))

        expect(reader.password_for('TestNetwork')).to be_nil
      end

      it 'returns nil for general errors that report a missing item' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 1, command: 'security', text: 'could not be found'))

        expect(reader.password_for('TestNetwork')).to be_nil
      end

      it 'raises a domain error when keychain access is denied' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 45, command: 'security', text: ''))

        expect { reader.password_for('TestNetwork') }
          .to raise_error(WifiWand::KeychainAccessDeniedError,
            "Keychain access denied for network 'TestNetwork'. Please grant access when prompted")
      end

      it 'raises a domain error when the keychain prompt is cancelled' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 128, command: 'security', text: ''))

        expect { reader.password_for('TestNetwork') }
          .to raise_error(WifiWand::KeychainAccessCancelledError,
            "Keychain access cancelled for network 'TestNetwork'")
      end

      it 'raises a domain error for non-interactive keychain access' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 51, command: 'security', text: ''))

        expect { reader.password_for('TestNetwork') }
          .to raise_error(WifiWand::KeychainNonInteractiveError,
            "Cannot access keychain for network 'TestNetwork' in non-interactive environment")
      end

      it 'raises a domain error for invalid search parameters' do
        allow(command_runner).to receive(:call)
          .and_raise(os_command_error(exitstatus: 25, command: 'security', text: ''))

        expect { reader.password_for('TestNetwork') }
          .to raise_error(WifiWand::KeychainError,
            "Invalid keychain search parameters for network 'TestNetwork'")
      end

      it 'includes stderr text from expected-but-failing general errors' do
        error = WifiWand::CommandExecutor::OsCommandError.new(
          result: command_result(
            stderr:     'keychain database is locked',
            exitstatus: 1,
            command:    'security'
          )
        )
        allow(command_runner).to receive(:call).and_raise(error)

        expect { reader.password_for('TestNetwork') }
          .to raise_error(WifiWand::KeychainError,
            "Keychain error accessing password for network 'TestNetwork': keychain database is locked")
      end

      it 'raises detailed KeychainError for unknown exit codes' do
        error = os_command_error(exitstatus: 99, command: 'security', text: 'strange failure')
        allow(command_runner).to receive(:call).and_raise(error)

        expect { reader.password_for('TestNet') }
          .to raise_error(WifiWand::KeychainError,
            "Unknown keychain error (exit code 99) accessing password for network 'TestNet': strange failure")
      end
    end
  end
end
