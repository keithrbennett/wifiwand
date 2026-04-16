# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'

RSpec.describe WifiWand::MacOsWifiAuthHelper do
  describe WifiWand::MacOsWifiAuthHelper::Client do
    subject(:client) do
      described_class.new(
        out_stream_proc:    -> { out_stream },
        verbose_proc:       -> { verbose_flag },
        macos_version_proc: -> { macos_version }
      )
    end

    let(:out_stream) { StringIO.new }
    let(:verbose_flag) { false }
    let(:macos_version) { '14.0' }

    around do |example|
      original = ENV['WIFIWAND_DISABLE_MAC_HELPER']
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
      it 'returns a result with the SSID payload' do
        raw_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(payload: { 'ssid' => 'OfficeWiFi' })
        expect(client).to receive(:execute).with('current-network').and_return(raw_result)
        result = client.connected_network_name
        expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
        expect(result.payload).to eq('OfficeWiFi')
        expect(result).not_to be_location_services_blocked
      end

      it 'returns a result with nil payload when the helper does not respond' do
        raw_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
        expect(client).to receive(:execute).with('current-network').and_return(raw_result)
        result = client.connected_network_name
        expect(result.payload).to be_nil
        expect(result).not_to be_location_services_blocked
      end
    end

    describe '#scan_networks' do
      it 'returns a result with network data payload' do
        raw_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new(
          payload: { 'networks' => [{ 'ssid' => 'Cafe' }] }
        )
        expect(client).to receive(:execute).with('scan-networks').and_return(raw_result)
        result = client.scan_networks
        expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
        expect(result.payload).to eq([{ 'ssid' => 'Cafe' }])
        expect(result).not_to be_location_services_blocked
      end

      it 'returns a result with empty array payload when the helper does not respond' do
        raw_result = WifiWand::MacOsWifiAuthHelper::HelperQueryResult.new
        expect(client).to receive(:execute).with('scan-networks').and_return(raw_result)
        result = client.scan_networks
        expect(result.payload).to eq([])
        expect(result).not_to be_location_services_blocked
      end
    end

    describe '#location_services_blocked?' do
      it 'returns true when the last helper error came from Location Services' do
        client.send(:handle_error, 'Location Services authorization timed out')
        expect(client.location_services_blocked?).to be(true)
      end

      it 'returns false when the last helper error was unrelated' do
        client.send(:handle_error, 'unexpected failure')
        expect(client.location_services_blocked?).to be(false)
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

        it 'returns an empty result without invoking the executable' do
          expect(Open3).not_to receive(:capture3)
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to be_nil
          expect(result).not_to be_location_services_blocked
        end
      end

      context 'when the helper command succeeds' do
        let(:status) { instance_double(Process::Status, success?: true) }

        before do
          allow(Open3).to receive(:capture3)
            .with('/tmp/helper', command)
            .and_return(['{"status":"ok","payload":1}', '', status])
        end

        it 'returns a result with the parsed payload' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to eq('status' => 'ok', 'payload' => 1)
          expect(result).not_to be_location_services_blocked
        end
      end

      context 'when the helper exits with a non-zero status' do
        let(:status) { instance_double(Process::Status, success?: false, exitstatus: 64) }

        before do
          allow(Open3).to receive(:capture3).and_return(['', 'boom', status])
        end

        it 'logs the failure and returns an empty result' do
          expect(client).to receive(:log_verbose).with('helper exited with status 64: boom')
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to be_nil
        end
      end

      context 'when the helper output cannot be parsed' do
        let(:status) { instance_double(Process::Status, success?: true) }

        before do
          allow(Open3).to receive(:capture3).and_return(['{}', '', status])
          allow(client).to receive(:parse_json).and_return(nil)
        end

        it 'returns an empty result' do
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to be_nil
        end
      end

      context 'when the helper reports an error status' do
        let(:status) { instance_double(Process::Status, success?: true) }

        before do
          allow(Open3).to receive(:capture3)
            .and_return(['{"status":"error","error":"Location Services denied"}', '', status])
        end

        it 'delegates to handle_error and returns a result with location_services_blocked' do
          expect(client).to receive(:handle_error).with('Location Services denied')
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result).to be_location_services_blocked
          expect(result.error_message).to eq('Location Services denied')
        end
      end

      context 'when the executable is missing' do
        before do
          allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT.new('wifiwand-helper'))
        end

        it 'logs the error and returns an empty result' do
          expect(client).to receive(:log_verbose).with(/helper executable missing:/)
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to be_nil
        end
      end

      context 'when an unexpected error occurs' do
        before do
          allow(Open3).to receive(:capture3).and_raise(StandardError, 'boom')
        end

        it 'logs the failure and returns an empty result' do
          expect(client).to receive(:log_verbose).with("helper command 'scan-networks' failed: boom")
          result = execute_command
          expect(result).to be_a(WifiWand::MacOsWifiAuthHelper::HelperQueryResult)
          expect(result.payload).to be_nil
        end
      end
    end

    describe '#ensure_helper_installed' do
      let(:helper_path) { '/tmp/helper' }

      before do
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:installed_executable_path).and_return(helper_path)
      end

      context 'when the helper executable is present and valid' do
        it 'returns immediately without reinstalling' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true)
          expect(WifiWand::MacOsWifiAuthHelper).not_to receive(:ensure_helper_installed)
          client.send(:ensure_helper_installed)
        end

        it 'caches successful validation for subsequent calls' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true).once
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true).once

          2.times { client.send(:ensure_helper_installed) }
        end
      end

      context 'when the helper executable is missing' do
        it 'installs the helper' do
          expect(File).to receive(:executable?).with(helper_path).and_return(false)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
          expect(client).to receive(:log_verbose).with('helper not installed; running installer')
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed).with(out_stream: nil)
          client.send(:ensure_helper_installed)
        end
      end

      context 'when the helper executable is present but invalid' do
        it 'attempts reinstall through the module installer' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
          expect(client).to receive(:log_verbose)
            .with('existing helper install failed validation; attempting reinstall')
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed).with(out_stream: nil)
          client.send(:ensure_helper_installed)
        end

        it 'disables the helper and emits repair guidance when reinstall fails' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
          allow(client).to receive(:log_verbose)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed)
            .and_raise(StandardError, 'boom')

          client.send(:ensure_helper_installed)

          expect(out_stream.string).to include('failed to install helper (boom)')
          expect(out_stream.string).to include('wifi-wand-macos-setup --repair')
          expect(client.instance_variable_get(:@disabled)).to be(true)
        end
      end

      context 'when the helper is missing and installation raises an error' do
        it 'disables the helper without a repair-specific warning' do
          expect(File).to receive(:executable?).with(helper_path).and_return(false)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
          allow(client).to receive(:log_verbose)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed)
            .and_raise(StandardError, 'boom')

          client.send(:ensure_helper_installed)

          expect(out_stream.string).to include('failed to install helper (boom)')
          expect(out_stream.string).not_to include('wifi-wand-macos-setup --repair')
          expect(client.instance_variable_get(:@disabled)).to be(true)
        end
      end

      context 'when reinstall succeeds after validation failure' do
        it 'marks the helper as verified for later calls' do
          expect(File).to receive(:executable?).with(helper_path).and_return(true).once
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?)
            .and_return(false).once
          allow(client).to receive(:log_verbose)
          expect(WifiWand::MacOsWifiAuthHelper).to receive(:ensure_helper_installed)
            .with(out_stream: nil).once

          2.times { client.send(:ensure_helper_installed) }
        end
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

      it 'includes repair guidance when an existing helper install is corrupt' do
        client.send(:emit_install_failure, 'boom', repair_required: true)
        expect(out_stream.string).to include('wifi-wand-macos-setup --repair')
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

  describe '.install_helper_bundle' do
    let(:out_stream) { StringIO.new }
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-install-spec') }
    let(:versioned_install_dir) { File.join(temp_dir, 'installed') }
    let(:installed_bundle_path) { File.join(versioned_install_dir, described_class::BUNDLE_NAME) }
    let(:installed_executable_path) do
      File.join(installed_bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:source_bundle_path) { File.join(temp_dir, 'source', described_class::BUNDLE_NAME) }
    let(:source_executable_path) do
      File.join(source_bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:source_code_resources_path) do
      File.join(source_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
    end
    let(:manifest_path) { File.join(versioned_install_dir, 'VERSION') }

    before do
      allow(described_class).to receive_messages(
        versioned_install_dir:     versioned_install_dir,
        installed_bundle_path:     installed_bundle_path,
        installed_executable_path: installed_executable_path,
        source_bundle_path:        source_bundle_path,
        helper_version:            '9.9.9'
      )

      create_helper_bundle(source_bundle_path, help_text: 'source helper')
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'installs the helper via a staged copy and writes the version manifest' do
      described_class.install_helper_bundle(out_stream: out_stream)

      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.symlink?(installed_bundle_path)).to be(true)
      expect(File.read(manifest_path)).to eq('9.9.9')
      expect(out_stream.string).to include('Installing wifiwand macOS helper...')
      expect(out_stream.string).to include('Helper bundle installed from pre-signed binary.')
    end

    it 'does not publish a bundle when staged validation fails on first install' do
      File.write(source_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, source_executable_path)

      expect do
        described_class.install_helper_bundle(out_stream: out_stream)
      end.to raise_error(RuntimeError, 'Staged helper installation failed validation.')

      expect(File).not_to exist(installed_bundle_path)
      expect(File).not_to exist(manifest_path)
    end

    it 'leaves the legacy bundle in place if executable migration fails' do
      create_helper_bundle(installed_bundle_path, help_text: 'existing helper')
      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)
      legacy_info_plist_path = File.join(installed_bundle_path, 'Contents', 'Info.plist')
      legacy_code_resources_path =
        File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')
      original_info_plist = File.read(legacy_info_plist_path)
      original_code_resources = File.read(legacy_code_resources_path)

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_executable_path
          raise StandardError, 'publish failed'
        end

        original.call(source, destination)
      end

      expect do
        described_class.install_helper_bundle(out_stream: out_stream)
      end.to raise_error(StandardError, 'publish failed')

      expect(File.read(installed_executable_path)).to eq("#!/bin/sh\nexit 1\n")
      expect(File.read(legacy_info_plist_path)).to eq(original_info_plist)
      expect(File.read(legacy_code_resources_path)).to eq(original_code_resources)
      expect(File).to exist(installed_bundle_path)
      expect(File).not_to exist(manifest_path)
    end

    it 'keeps installed_bundle_path visible while migrating a legacy install' do
      create_helper_bundle(installed_bundle_path, help_text: 'existing helper')
      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)

      observed_path_states = []

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_executable_path
          observed_path_states << File.exist?(installed_bundle_path)
          observed_path_states << File.exist?(installed_executable_path)
        end

        original.call(source, destination)
      end

      described_class.install_helper_bundle(out_stream: nil)

      expect(observed_path_states).to eq([true, true])
      expect(File).to exist(installed_bundle_path)
      expect(File.symlink?(installed_bundle_path)).to be(false)
      expect(File.symlink?(installed_executable_path)).to be(true)
      expect(File.read(File.join(installed_bundle_path, 'Contents', '_CodeSignature', 'CodeResources')))
        .to eq(File.read(source_code_resources_path))
      expect(described_class.helper_installed_and_valid?).to be(true)
    end

    it 'keeps installed_bundle_path visible while replacing an existing symlinked install' do
      described_class.install_helper_bundle(out_stream: nil)

      File.write(installed_executable_path, "#!/bin/sh\nexit 1\n")
      FileUtils.chmod(0o755, installed_executable_path)

      observed_path_states = []

      allow(File).to receive(:rename).and_wrap_original do |original, source, destination|
        if source.include?('.link-') && destination == installed_bundle_path
          observed_path_states << File.exist?(installed_bundle_path)
          observed_path_states << File.symlink?(installed_bundle_path)
        end

        original.call(source, destination)
      end

      described_class.install_helper_bundle(out_stream: nil)

      expect(observed_path_states).to eq([true, true])
      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.symlink?(installed_bundle_path)).to be(true)
    end

    it 'serializes concurrent first-run installs so only one copy executes' do
      installation_started = Queue.new
      allow(described_class)
        .to receive(:stage_helper_bundle).and_wrap_original do |original, staged_bundle_path|
        installation_started << :started
        sleep(0.1)
        original.call(staged_bundle_path)
      end

      first_thread = Thread.new { described_class.install_helper_bundle(out_stream: nil) }
      installation_started.pop

      second_thread = Thread.new { described_class.install_helper_bundle(out_stream: nil) }

      [first_thread, second_thread].each(&:join)

      expect(described_class).to have_received(:stage_helper_bundle).once
      expect(described_class.helper_installed_and_valid?).to be(true)
      expect(File.read(manifest_path)).to eq('9.9.9')
    end
  end

  describe '.helper_bundle_valid?' do
    let(:temp_dir) { Dir.mktmpdir('wifiwand-helper-valid-spec') }
    let(:bundle_path) { File.join(temp_dir, described_class::BUNDLE_NAME) }
    let(:executable_path) do
      File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    end
    let(:info_plist_path) { File.join(bundle_path, 'Contents', 'Info.plist') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'validates the helper with the help command expected by the shipped executable' do
      FileUtils.mkdir_p(File.dirname(executable_path))
      File.write(executable_path, <<~SH)
        #!/bin/sh
        if [ "$1" = "help" ]; then
          echo "wifiwand helper usage"
          exit 0
        fi
        echo "unknown command: $1" >&2
        exit 64
      SH
      FileUtils.chmod(0o755, executable_path)

      FileUtils.mkdir_p(File.dirname(info_plist_path))
      File.write(info_plist_path, '<plist version="1.0">helper</plist>')

      expect(described_class.helper_bundle_valid?(bundle_path)).to be(true)
    end
  end

  def create_helper_bundle(bundle_path, help_text:)
    executable_path = File.join(bundle_path, 'Contents', 'MacOS', described_class::EXECUTABLE_NAME)
    info_plist_path = File.join(bundle_path, 'Contents', 'Info.plist')
    code_resources_path = File.join(bundle_path, 'Contents', '_CodeSignature', 'CodeResources')

    FileUtils.mkdir_p(File.dirname(executable_path))
    File.write(executable_path, <<~SH)
      #!/bin/sh
      echo "#{help_text}"
    SH
    FileUtils.chmod(0o755, executable_path)

    FileUtils.mkdir_p(File.dirname(info_plist_path))
    File.write(info_plist_path, "<plist version=\"1.0\">#{help_text}</plist>")

    FileUtils.mkdir_p(File.dirname(code_resources_path))
    File.write(code_resources_path, "signature=#{help_text}\n")
  end
end
