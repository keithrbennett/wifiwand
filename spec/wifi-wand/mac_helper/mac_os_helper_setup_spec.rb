# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'wifi-wand/mac_helper/mac_os_helper_setup'

RSpec.describe WifiWand::MacOsHelperSetup do
  subject(:setup) { described_class.new(out_stream: out_stream, macos_version_proc: -> { macos_version }) }

  let(:out_stream) { StringIO.new }
  let(:macos_version) { '14.0' }

  # ---------------------------------------------------------------------------
  # Result value object
  # ---------------------------------------------------------------------------
  describe WifiWand::MacOsHelperSetup::Result do
    def build(installed: false, valid: false, authorized: false, message: '')
      described_class.new(
        installed:          installed,
        valid:              valid,
        authorized:         authorized,
        permission_message: message
      )
    end

    describe '#installed?' do
      it 'returns true when installed' do
        expect(build(installed: true).installed?).to be(true)
      end

      it 'returns false when not installed' do
        expect(build(installed: false).installed?).to be(false)
      end
    end

    describe '#valid?' do
      it 'returns true when valid' do
        expect(build(valid: true).valid?).to be(true)
      end

      it 'returns false when not valid' do
        expect(build(valid: false).valid?).to be(false)
      end
    end

    describe '#authorized?' do
      it 'returns true when authorized' do
        expect(build(authorized: true).authorized?).to be(true)
      end

      it 'returns false when not authorized' do
        expect(build(authorized: false).authorized?).to be(false)
      end
    end

    describe '#setup_complete?' do
      it 'returns true when installed, valid, and authorized' do
        expect(build(installed: true, valid: true, authorized: true).setup_complete?).to be(true)
      end

      it 'returns false when not installed' do
        expect(build(installed: false, valid: false, authorized: false).setup_complete?).to be(false)
      end

      it 'returns false when installed but not valid' do
        expect(build(installed: true, valid: false, authorized: true).setup_complete?).to be(false)
      end

      it 'returns false when valid but not authorized' do
        expect(build(installed: true, valid: true, authorized: false).setup_complete?).to be(false)
      end
    end

    describe '#reinstall_recommended?' do
      it 'returns true when installed but not valid' do
        expect(build(installed: true, valid: false).reinstall_recommended?).to be(true)
      end

      it 'returns false when not installed at all' do
        expect(build(installed: false, valid: false).reinstall_recommended?).to be(false)
      end

      it 'returns false when installed and valid' do
        expect(build(installed: true, valid: true).reinstall_recommended?).to be(false)
      end
    end

    describe '#steps_needed' do
      it 'returns [] when setup is complete' do
        expect(build(installed: true, valid: true, authorized: true).steps_needed).to eq([])
      end

      it 'returns [:install_helper, :grant_permission] when nothing is installed' do
        expect(build(installed: false, valid: false, authorized: false).steps_needed)
          .to eq(%i[install_helper grant_permission])
      end

      it 'returns [:reinstall_helper, :grant_permission] when installed but invalid' do
        expect(build(installed: true, valid: false, authorized: false).steps_needed)
          .to eq(%i[reinstall_helper grant_permission])
      end

      it 'returns [:grant_permission] when installed and valid but not authorized' do
        expect(build(installed: true, valid: true, authorized: false).steps_needed)
          .to eq(%i[grant_permission])
      end

      it 'returns [] when helper setup is not applicable' do
        result = build(installed: false, valid: false, authorized: false)
        result.helper_applicable = false
        expect(result.steps_needed).to eq([])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#helper_support_status
  # ---------------------------------------------------------------------------
  describe '#helper_support_status' do
    context 'when macOS is older than Sonoma' do
      let(:macos_version) { '13.6.1' }

      it 'reports the helper setup as not applicable' do
        status = setup.helper_support_status
        expect(status).to be_known
        expect(status).to be_unsupported
        expect(status).not_to be_applicable
      end
    end

    context 'when macOS is exactly Sonoma' do
      let(:macos_version) { '14.0' }

      it 'reports the helper setup as supported' do
        expect(WifiWand::MacOsHelperBundle)
          .to receive(:helper_support_status_for_macos_version).with('14.0').and_call_original

        status = setup.helper_support_status
        expect(status).to be_known
        expect(status).to be_supported
        expect(status).to be_applicable
      end
    end

    context 'when macOS has build metadata' do
      let(:macos_version) { '15.6 (24G84)' }

      it 'reports the helper setup as supported' do
        status = setup.helper_support_status
        expect(status).to be_supported
        expect(status).to be_applicable
      end
    end

    context 'when macOS version detection returns nil' do
      let(:macos_version) { nil }

      it 'preserves the existing setup path because support cannot be proven unsupported' do
        status = setup.helper_support_status
        expect(status).to be_unknown
        expect(status).to be_applicable
      end
    end

    context 'when macOS version detection returns malformed text' do
      let(:macos_version) { 'developer seed' }

      it 'preserves the existing setup path because support cannot be proven unsupported' do
        status = setup.helper_support_status
        expect(status).to be_unknown
        expect(status).to be_applicable
      end
    end

    context 'when no version proc is injected' do
      subject(:setup) { described_class.new(out_stream: out_stream) }

      it 'uses the centralized macOS version detector' do
        allow(WifiWand::MacOsHelperBundle).to receive(:detect_macos_version).and_return('14.0')

        expect(setup.helper_support_status.macos_version).to eq('14.0')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#check_status
  # ---------------------------------------------------------------------------
  describe '#check_status' do
    let(:helper_path) { '/tmp/fake-helper' }

    before do
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_executable_path).and_return(helper_path)
    end

    context 'when the helper is not installed' do
      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(false)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'returns installed: false, valid: false, authorized: false' do
        status = setup.check_status
        expect(status.installed?).to be(false)
        expect(status.valid?).to be(false)
        expect(status.authorized?).to be(false)
        expect(status.setup_complete?).to be(false)
      end

      it 'does not attempt to invoke the helper executable' do
        expect(WifiWand::MacOsHelperBundle).not_to receive(:run_bounded_helper_command)
        setup.check_status
      end
    end

    context 'when the helper is installed but structurally invalid (reinstall recommended)' do
      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'returns installed: true, valid: false, authorized: false' do
        status = setup.check_status
        expect(status.installed?).to be(true)
        expect(status.valid?).to be(false)
        expect(status.authorized?).to be(false)
        expect(status.reinstall_recommended?).to be(true)
      end

      it 'does not invoke the broken executable to probe authorization' do
        expect(WifiWand::MacOsHelperBundle).not_to receive(:run_bounded_helper_command)
        setup.check_status
      end

      it 'includes :reinstall_helper and :grant_permission in steps_needed' do
        expect(setup.check_status.steps_needed).to eq(%i[reinstall_helper grant_permission])
      end
    end

    context 'when the helper is installed but location permission is not granted' do
      let(:ok_status) { instance_double(Process::Status, success?: true) }
      let(:response)  { JSON.dump('authorized' => false, 'message' => 'Not authorized by user') }

      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:run_bounded_helper_command).with(helper_path, 'check-permission')
          .and_return(stdout: response, stderr: '', status: ok_status)
      end

      it 'returns installed: true, valid: true, authorized: false' do
        status = setup.check_status
        expect(status.installed?).to be(true)
        expect(status.valid?).to be(true)
        expect(status.authorized?).to be(false)
        expect(status.permission_message).to eq('Not authorized by user')
      end

      it 'includes only :grant_permission in steps_needed' do
        expect(setup.check_status.steps_needed).to eq(%i[grant_permission])
      end
    end

    context 'when the helper is installed and fully authorized' do
      let(:ok_status) { instance_double(Process::Status, success?: true) }
      let(:response)  { JSON.dump('authorized' => true, 'message' => 'Authorized') }

      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:run_bounded_helper_command).with(helper_path, 'check-permission')
          .and_return(stdout: response, stderr: '', status: ok_status)
      end

      it 'returns setup_complete? true' do
        status = setup.check_status
        expect(status.setup_complete?).to be(true)
        expect(status.steps_needed).to eq([])
      end
    end

    context 'when check-permission returns invalid JSON' do
      let(:ok_status) { instance_double(Process::Status, success?: true) }

      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:run_bounded_helper_command).with(helper_path, 'check-permission')
          .and_return(stdout: '{invalid', stderr: '', status: ok_status)
      end

      it 'returns authorized: false with a descriptive message' do
        status = setup.check_status
        expect(status.authorized?).to be(false)
        expect(status.permission_message).to match(/parse/)
      end
    end

    context 'when the helper authorization probe times out' do
      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:run_bounded_helper_command).with(helper_path, 'check-permission')
          .and_return(nil)
      end

      it 'returns authorized: false with an unknown permission status message' do
        status = setup.check_status
        expect(status.authorized?).to be(false)
        expect(status.permission_message).to eq('Permission status unknown')
      end
    end

    context 'when the macOS version is older than the helper minimum' do
      let(:macos_version) { '13.6.1' }

      it 'returns a not-applicable result without checking installed files' do
        expect(File).not_to receive(:executable?)
        expect(WifiWand::MacOsHelperBundle).not_to receive(:helper_installed_and_valid?)

        status = setup.check_status
        expect(status).to be_not_applicable
        expect(status.steps_needed).to eq([])
        expect(status.permission_message).to include('not applicable')
      end
    end

    context 'when the macOS version is missing' do
      let(:macos_version) { nil }

      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(false)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'preserves the existing setup path instead of silently skipping setup' do
        status = setup.check_status
        expect(status).to be_helper_applicable
        expect(status.steps_needed).to eq(%i[install_helper grant_permission])
      end
    end

    context 'when the macOS version is malformed' do
      let(:macos_version) { 'developer seed' }

      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(false)
        allow(WifiWand::MacOsHelperBundle).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'preserves the existing setup path instead of silently skipping setup' do
        status = setup.check_status
        expect(status).to be_helper_applicable
        expect(status.steps_needed).to eq(%i[install_helper grant_permission])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#install_helper
  # ---------------------------------------------------------------------------
  describe '#install_helper' do
    it 'delegates to MacOsHelperBundle.ensure_helper_installed with the output stream' do
      expect(WifiWand::MacOsHelperBundle)
        .to receive(:ensure_helper_installed).with(out_stream: out_stream)
      setup.install_helper
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#reinstall_helper
  # ---------------------------------------------------------------------------
  describe '#reinstall_helper' do
    context 'when reinstall succeeds and validation passes' do
      before do
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:install_helper_bundle).with(out_stream: out_stream, force: true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive_messages(helper_installed_and_valid?: true, installed_bundle_path: '/fake/bundle')
      end

      it 'returns the installed bundle path' do
        expect(setup.reinstall_helper).to eq('/fake/bundle')
      end
    end

    context 'when reinstall validation fails' do
      before do
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:install_helper_bundle).with(out_stream: out_stream, force: true)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'raises an error with a user-actionable message' do
        expect { setup.reinstall_helper }
          .to raise_error(RuntimeError, /reinstallation failed/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#remove_helper
  # ---------------------------------------------------------------------------
  describe '#remove_helper' do
    let(:install_dir) { '/tmp/fake-wifiwand-helper-install' }

    before do
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:versioned_install_dir).and_return(install_dir)
    end

    it 'removes the versioned helper installation directory idempotently' do
      expect(FileUtils).to receive(:rm_rf).with(install_dir)
      setup.remove_helper
    end

    it 'returns the target installation directory path' do
      allow(FileUtils).to receive(:rm_rf).with(install_dir)
      expect(setup.remove_helper).to eq(install_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#open_location_settings
  # ---------------------------------------------------------------------------
  describe '#open_location_settings' do
    it 'opens the macOS Location Services system preferences URL' do
      expect(setup).to receive(:system).with(
        'open',
        'x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices'
      )
      setup.open_location_settings
    end
  end
end
