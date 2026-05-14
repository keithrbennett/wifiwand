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

      it 'handles different keychain scenarios' do
        test_cases = [
          [os_command_error(exitstatus: 44, command: 'security', text: ''), nil],
          [
            os_command_error(exitstatus: 45, command: 'security', text: ''),
            WifiWand::KeychainAccessDeniedError,
          ],
          [
            os_command_error(exitstatus: 128, command: 'security', text: ''),
            WifiWand::KeychainAccessCancelledError,
          ],
          [
            os_command_error(exitstatus: 51, command: 'security', text: ''),
            WifiWand::KeychainNonInteractiveError,
          ],
          [os_command_error(exitstatus: 25, command: 'security', text: ''), WifiWand::KeychainError],
          [os_command_error(exitstatus: 1, command: 'security', text: 'could not be found'), nil],
          [
            os_command_error(exitstatus: 1, command: 'security', text: 'other error'),
            WifiWand::KeychainError,
          ],
          %w[mypassword123 mypassword123],
        ]

        test_cases.each do |response, expected|
          if response.is_a?(Exception)
            allow(command_runner).to receive(:call).and_raise(response)
          else
            allow(command_runner).to receive(:call).and_return(command_result(stdout: response))
          end

          if expected.is_a?(Class) && expected < Exception
            expect { reader.password_for('TestNetwork') }.to raise_error(expected)
          else
            expect(reader.password_for('TestNetwork')).to eq(expected)
          end
        end
      end

      it 'raises detailed KeychainError for unknown exit codes' do
        error = os_command_error(exitstatus: 99, command: 'security', text: 'strange failure')
        allow(command_runner).to receive(:call).and_raise(error)

        expect { reader.password_for('TestNet') }.to raise_error(WifiWand::KeychainError)
      end
    end
  end
end
