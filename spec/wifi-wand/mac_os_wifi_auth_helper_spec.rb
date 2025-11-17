# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe WifiWand::MacOsWifiAuthHelper::Client do
  subject(:client) do
    described_class.new(
      out_stream_proc: -> { out_stream },
      verbose_proc: -> { verbose_flag },
      macos_version_proc: -> { macos_version }
    )
  end

  let(:out_stream) { StringIO.new }
  let(:verbose_flag) { false }
  let(:macos_version) { '14.0' }


  around do |example|
    original = ENV.fetch('WIFIWAND_DISABLE_MAC_HELPER', nil)
    ENV.delete('WIFIWAND_DISABLE_MAC_HELPER')
    example.run
  ensure
    ENV['WIFIWAND_DISABLE_MAC_HELPER'] = original
  end

  describe '#available?' do
    context 'when the helper is already disabled' do
      before { client.instance_variable_set(:@disabled, true) }

      it 'returns false' do
        expect(client.available?).to be(false)
      end
    end

    context 'when the disable env flag is set' do
      before { ENV['WIFIWAND_DISABLE_MAC_HELPER'] = '1' }

      it 'returns false' do
        expect(client.available?).to be(false)
      end
    end

    context 'when the macOS version is missing' do
      let(:macos_version) { nil }

      it 'returns false' do
        expect(client.available?).to be(false)
      end
    end

    context 'when the version string cannot be sanitized' do
      let(:macos_version) { 'developer seed' }

      it 'returns false' do
        expect(client.available?).to be(false)
      end
    end

    context 'when the version is older than the minimum helper version' do
      let(:macos_version) { '13.6.1' }

      it 'returns false' do
        expect(client.available?).to be(false)
      end
    end

    context 'when the version meets the minimum helper version' do
      let(:macos_version) { '15.0 (24A335)' }

      it 'returns true' do
        expect(client.available?).to be(true)
      end
    end
  end

  describe '#connected_network_name' do
    it 'returns the SSID from the helper payload' do
      expect(client).to receive(:execute).with('current-network').and_return('ssid' => 'OfficeWiFi')
      expect(client.connected_network_name).to eq('OfficeWiFi')
    end

    it 'returns nil when the helper does not respond' do
      expect(client).to receive(:execute).with('current-network').and_return(nil)
      expect(client.connected_network_name).to be_nil
    end
  end

  describe '#scan_networks' do
    it 'returns network data from the helper payload' do
      payload = { 'networks' => [{ 'ssid' => 'Cafe' }] }
      expect(client).to receive(:execute).with('scan-networks').and_return(payload)
      expect(client.scan_networks).to eq(payload['networks'])
    end

    it 'returns an empty array when the helper does not respond' do
      expect(client).to receive(:execute).with('scan-networks').and_return(nil)
      expect(client.scan_networks).to eq([])
    end
  end

  describe '#execute' do
    subject(:execute_command) { client.send(:execute, command) }

    let(:command) { 'scan-networks' }
    let(:helper_available) { true }

    before do
      allow(client).to receive(:available?).and_return(helper_available)
      allow(client).to receive(:ensure_helper_installed)
      allow(WifiWand::MacOsWifiAuthHelper).to receive(:installed_executable_path).and_return('/tmp/helper')
    end

    context 'when the helper is unavailable' do
      let(:helper_available) { false }

      it 'returns nil without invoking the executable' do
        expect(Open3).not_to receive(:capture3)
        expect(execute_command).to be_nil
      end
    end

    context 'when the helper command succeeds' do
      let(:status) { instance_double(Process::Status, success?: true) }

      before do
        allow(Open3).to receive(:capture3)
          .with('/tmp/helper', command)
          .and_return(['{"status":"ok","payload":1}', '', status])
      end

      it 'returns the parsed payload' do
        expect(execute_command).to eq('status' => 'ok', 'payload' => 1)
      end
    end

    context 'when the helper exits with a non-zero status' do
      let(:status) { instance_double(Process::Status, success?: false, exitstatus: 64) }

      before do
        allow(Open3).to receive(:capture3).and_return(['', 'boom', status])
      end

      it 'logs the failure and returns nil' do
        expect(client).to receive(:log_verbose).with('helper exited with status 64: boom')
        expect(execute_command).to be_nil
      end
    end

    context 'when the helper output cannot be parsed' do
      let(:status) { instance_double(Process::Status, success?: true) }

      before do
        allow(Open3).to receive(:capture3).and_return(['{}', '', status])
        allow(client).to receive(:parse_json).and_return(nil)
      end

      it 'returns nil' do
        expect(execute_command).to be_nil
      end
    end

    context 'when the helper reports an error status' do
      let(:status) { instance_double(Process::Status, success?: true) }

      before do
        allow(Open3).to receive(:capture3)
          .and_return(['{"status":"error","error":"Location Services denied"}', '', status])
      end

      it 'delegates to handle_error and returns nil' do
        expect(client).to receive(:handle_error).with('Location Services denied')
        expect(execute_command).to be_nil
      end
    end

    context 'when the executable is missing' do
      before do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new('wifiwand-helper'))
      end

      it 'logs the error and returns nil' do
        expect(client).to receive(:log_verbose).with(/helper executable missing:/)
        expect(execute_command).to be_nil
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError, 'boom')
      end

      it 'logs the failure and returns nil' do
        expect(client).to receive(:log_verbose).with("helper command 'scan-networks' failed: boom")
        expect(execute_command).to be_nil
      end
    end
  end

  describe '#ensure_helper_installed' do
    let(:helper_path) { '/tmp/helper' }

    before do
      allow(WifiWand::MacOsWifiAuthHelper).to receive(:installed_executable_path).and_return(helper_path)
    end

    it 'returns immediately when the helper executable already exists' do
      expect(File).to receive(:executable?).with(helper_path).and_return(true)
      expect(WifiWand::MacOsWifiAuthHelper).not_to receive(:ensure_helper_installed)
      client.send(:ensure_helper_installed)
    end

    it 'installs the helper when the executable is missing' do
      expect(File).to receive(:executable?).with(helper_path).and_return(false)
      expect(client).to receive(:log_verbose).with('helper not installed; running installer')
      expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed).with(out_stream: nil)
      client.send(:ensure_helper_installed)
    end

    it 'disables the helper when installation raises an error' do
      expect(File).to receive(:executable?).with(helper_path).and_return(false)
      allow(client).to receive(:log_verbose)
      expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed).and_raise(
        StandardError, 'boom')

      client.send(:ensure_helper_installed)

      expect(out_stream.string).to include('failed to install helper (boom)')
      expect(client.instance_variable_get(:@disabled)).to be(true)
    end
  end

  describe '#parse_json' do
    it 'returns parsed data for valid JSON' do
      expect(client.send(:parse_json, '{"foo":1}')).to eq('foo' => 1)
    end

    it 'logs an error when parsing fails' do
      expect(client).to receive(:log_verbose).with(/failed to parse helper JSON:/)
      expect(client.send(:parse_json, '{invalid-json')).to be_nil
    end
  end

  describe '#handle_error' do
    it 'emits a location warning when permissions are denied' do
      expect(client).to receive(:emit_location_warning)
      client.send(:handle_error, 'Location Services denied by user')
    end

    it 'logs non-location failures' do
      expect(client).to receive(:log_verbose).with('helper error: unexpected failure')
      client.send(:handle_error, 'unexpected failure')
    end

    it 'ignores nil messages' do
      expect(client).not_to receive(:log_verbose)
      client.send(:handle_error, nil)
    end
  end

  describe '#emit_location_warning' do
    it 'prints the warning only once' do
      client.send(:emit_location_warning)
      client.send(:emit_location_warning)
      occurrences = out_stream.string.scan('Location Services denied').size
      expect(occurrences).to eq(1)
    end
  end

  describe '#emit_install_failure' do
    it 'prints the failure message to the output stream' do
      client.send(:emit_install_failure, 'boom')
      expect(out_stream.string).to include('failed to install helper (boom)')
    end
  end

  describe '#log_verbose' do
    context 'when verbose mode is enabled' do
      let(:verbose_flag) { true }

      it 'prints the message with the helper prefix' do
        client.send(:log_verbose, 'details')
        expect(out_stream.string).to include('wifiwand helper: details')
      end
    end

    context 'when verbose mode is disabled' do
      let(:verbose_flag) { false }

      it 'does not print anything' do
        client.send(:log_verbose, 'details')
        expect(out_stream.string).to eq('')
      end
    end
  end

  describe '#sanitize_version_string' do
    it 'keeps only numeric segments from versions with build metadata in parentheses' do
      expect(client.send(:sanitize_version_string, '15.6 (24A335)')).to eq('15.6')
    end

    it 'removes prerelease suffixes like beta tags' do
      expect(client.send(:sanitize_version_string, '15.6.1-beta2')).to eq('15.6.1')
    end

    it 'returns nil when the version does not include numeric components' do
      expect(client.send(:sanitize_version_string, 'unknown')).to be_nil
    end
  end
end
