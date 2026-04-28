# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/mac_helper/mac_os_swift_runtime'

module WifiWand
  describe MacOsSwiftRuntime do
    let(:out_stream) { StringIO.new }
    let(:verbose) { true }
    let(:command_runner) { instance_double(Proc) }
    let(:runtime) do
      described_class.new(
        command_runner:  command_runner,
        out_stream_proc: -> { out_stream },
        verbose_proc:    -> { verbose }
      )
    end

    describe '#swift_and_corewlan_present?' do
      it 'probes Swift/CoreWLAN availability once and memoizes the result' do
        expect(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false).once
          .and_return(command_result(stdout: ''))

        2.times do
          expect(runtime.swift_and_corewlan_present?).to be(true)
        end
      end

      it 'returns false for Swift/CoreWLAN probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false)
          .and_raise(os_command_error(exitstatus: 127, command: 'swift', text: ''))

        expect(runtime.swift_and_corewlan_present?).to be(false)
      end

      it 'logs a targeted message when Swift is not installed' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false)
          .and_raise(os_command_error(exitstatus: 127, command: 'swift', text: ''))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift command not found (exit code 127)')
      end

      it 'logs a targeted message when CoreWLAN is unavailable' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false)
          .and_raise(os_command_error(exitstatus: 1, command: 'swift', text: 'missing framework'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('CoreWLAN framework not available (exit code 1)')
      end

      it 'logs the command output for other OsCommandError probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false)
          .and_raise(os_command_error(exitstatus: 2, command: 'swift', text: 'toolchain mismatch'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Swift/CoreWLAN check failed with exit code 2')
        expect(out_stream.string).to include('toolchain mismatch')
      end

      it 'logs an unexpected-error message for non-command probe failures' do
        allow(command_runner).to receive(:call).with(['swift', '-e', 'import CoreWLAN'], false)
          .and_raise(StandardError.new('unexpected'))

        expect(runtime.swift_and_corewlan_present?).to be(false)
        expect(out_stream.string).to include('Unexpected error checking Swift/CoreWLAN: unexpected')
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
      it 'recognizes recoverable Swift/CoreWLAN connect failures' do
        error_text = "The operation couldn't be completed. tmpErr (code: 82)"

        expect(runtime.fallback_connect_error?(error_text)).to be(true)
      end

      it 'returns false for non-recoverable connect failures' do
        expect(runtime.fallback_connect_error?('permission denied')).to be(false)
      end
    end
  end
end
