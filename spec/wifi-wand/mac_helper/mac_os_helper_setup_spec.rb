# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'wifi-wand/mac_helper/mac_os_helper_setup'

RSpec.describe WifiWand::MacOsHelperSetup do
  subject(:setup) { described_class.new(out_stream: out_stream) }

  let(:out_stream) { StringIO.new }


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

    describe '#repair_recommended?' do
      it 'returns true when installed but not valid' do
        expect(build(installed: true, valid: false).repair_recommended?).to be(true)
      end

      it 'returns false when not installed at all' do
        expect(build(installed: false, valid: false).repair_recommended?).to be(false)
      end

      it 'returns false when installed and valid' do
        expect(build(installed: true, valid: true).repair_recommended?).to be(false)
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
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#check_status
  # ---------------------------------------------------------------------------
  describe '#check_status' do
    let(:helper_path) { '/tmp/fake-helper' }

    before do
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return(helper_path)
    end

    context 'when the helper is not installed' do
      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(false)
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'returns installed: false, valid: false, authorized: false' do
        status = setup.check_status
        expect(status.installed?).to be(false)
        expect(status.valid?).to be(false)
        expect(status.authorized?).to be(false)
        expect(status.setup_complete?).to be(false)
      end

      it 'does not attempt to invoke the helper executable' do
        expect(WifiWand::MacOsWifiAuthHelper).not_to receive(:run_bounded_helper_command)
        setup.check_status
      end
    end

    context 'when the helper is installed but structurally invalid (repair recommended)' do
      before do
        allow(File).to receive(:executable?).with(helper_path).and_return(true)
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'returns installed: true, valid: false, authorized: false' do
        status = setup.check_status
        expect(status.installed?).to be(true)
        expect(status.valid?).to be(false)
        expect(status.authorized?).to be(false)
        expect(status.repair_recommended?).to be(true)
      end

      it 'does not invoke the broken executable to probe authorization' do
        expect(WifiWand::MacOsWifiAuthHelper).not_to receive(:run_bounded_helper_command)
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
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsWifiAuthHelper)
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
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsWifiAuthHelper)
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
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsWifiAuthHelper)
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
        allow(WifiWand::MacOsWifiAuthHelper).to receive(:helper_installed_and_valid?).and_return(true)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:run_bounded_helper_command).with(helper_path, 'check-permission')
          .and_return(nil)
      end

      it 'returns authorized: false with an unknown permission status message' do
        status = setup.check_status
        expect(status.authorized?).to be(false)
        expect(status.permission_message).to eq('Permission status unknown')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MacOsHelperSetup#install_helper
  # ---------------------------------------------------------------------------
  describe '#install_helper' do
    it 'delegates to MacOsWifiAuthHelper.ensure_helper_installed with the output stream' do
      expect(WifiWand::MacOsWifiAuthHelper)
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
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:install_helper_bundle).with(out_stream: out_stream)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive_messages(helper_installed_and_valid?: true, installed_bundle_path: '/fake/bundle')
      end

      it 'returns the installed bundle path' do
        expect(setup.reinstall_helper).to eq('/fake/bundle')
      end
    end

    context 'when reinstall validation fails' do
      before do
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:install_helper_bundle).with(out_stream: out_stream)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:helper_installed_and_valid?).and_return(false)
      end

      it 'raises an error with a user-actionable message' do
        expect { setup.reinstall_helper }
          .to raise_error(RuntimeError, /reinstallation failed/)
      end
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
