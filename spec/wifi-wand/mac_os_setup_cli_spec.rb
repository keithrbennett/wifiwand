# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'wifi-wand/mac_os_setup_cli'

RSpec.describe WifiWand::MacOsSetupCli do
  before { allow_any_instance_of(described_class).to receive(:sleep) }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  let(:out_stream) { StringIO.new }
  let(:in_stream)  { StringIO.new("\n") } # simulates ENTER

  def build_result(installed: true, valid: true, authorized: false, message: 'Not authorized')
    WifiWand::MacOsHelperSetup::Result.new(
      installed:          installed,
      valid:              valid,
      authorized:         authorized,
      permission_message: message
    )
  end

  def build_cli(argv: [], setup: nil)
    described_class.new(
      argv:       argv,
      setup:      setup,
      out_stream: out_stream,
      in_stream:  in_stream
    )
  end

  # Shared setup mock that stubs the parts every scenario touches.
  def stub_setup(setup, initial_status:, post_status: nil)
    allow(setup).to receive(:check_status).and_return(initial_status, *(post_status ? [post_status] : []))
    allow(setup).to receive(:install_helper)
    allow(setup).to receive(:reinstall_helper)
    allow(setup).to receive(:open_location_settings)
    allow(WifiWand::MacOsWifiAuthHelper)
      .to receive_messages(installed_executable_path: '/fake/helper', installed_bundle_path: '/fake/bundle')
  end

  # ---------------------------------------------------------------------------
  # Early-exit when already complete
  # ---------------------------------------------------------------------------
  describe 'when setup is already complete' do
    let(:setup)  { instance_double(WifiWand::MacOsHelperSetup) }
    let(:status) { build_result(authorized: true) }

    before { stub_setup(setup, initial_status: status) }

    it 'returns exit code 0' do
      expect(build_cli(setup: setup).run).to eq(0)
    end

    it 'prints the completion message' do
      build_cli(setup: setup).run
      expect(out_stream.string).to include('setup is complete')
    end

    it 'does not prompt for ENTER' do
      build_cli(setup: setup).run
      expect(out_stream.string).not_to include('Press ENTER')
    end

    it 'does not call install_helper or reinstall_helper' do
      expect(setup).not_to receive(:install_helper)
      expect(setup).not_to receive(:reinstall_helper)
      build_cli(setup: setup).run
    end
  end

  # ---------------------------------------------------------------------------
  # --repair flag
  # ---------------------------------------------------------------------------
  describe '--repair flag' do
    let(:setup)          { instance_double(WifiWand::MacOsHelperSetup) }
    let(:complete_status) { build_result(authorized: true) }

    context 'when reinstall succeeds' do
      before do
        allow(setup).to receive(:reinstall_helper)
        stub_setup(setup, initial_status: complete_status)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:installed_bundle_path).and_return('/fake/bundle')
      end

      it 'calls reinstall_helper before the normal status check' do
        expect(setup).to receive(:reinstall_helper).ordered
        expect(setup).to receive(:check_status).and_return(complete_status).ordered
        build_cli(argv: ['--repair'], setup: setup).run
      end

      it 'prints a reinstall confirmation message' do
        build_cli(argv: ['--repair'], setup: setup).run
        expect(out_stream.string).to include('Reinstalling')
        expect(out_stream.string).to include('reinstalled at:')
      end

      it 'returns exit code 0 when the post-repair status is complete' do
        expect(build_cli(argv: ['--repair'], setup: setup).run).to eq(0)
      end
    end

    context 'when reinstall_helper raises an error' do
      before do
        allow(setup).to receive(:reinstall_helper).and_raise('bundle copy failed')
        allow(setup).to receive(:check_status).and_return(complete_status)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:installed_bundle_path).and_return('/fake/bundle')
      end

      it 'returns exit code 1' do
        expect(build_cli(argv: ['--repair'], setup: setup).run).to eq(1)
      end

      it 'prints the error message' do
        build_cli(argv: ['--repair'], setup: setup).run
        expect(out_stream.string).to include('bundle copy failed')
      end
    end

    context 'with --reinstall alias' do
      before do
        allow(setup).to receive(:reinstall_helper)
        stub_setup(setup, initial_status: complete_status)
        allow(WifiWand::MacOsWifiAuthHelper)
          .to receive(:installed_bundle_path).and_return('/fake/bundle')
      end

      it 'also triggers the repair path' do
        expect(setup).to receive(:reinstall_helper)
        build_cli(argv: ['--reinstall'], setup: setup).run
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper not installed → install path
  # ---------------------------------------------------------------------------
  describe 'when the helper is not installed' do
    let(:setup)           { instance_double(WifiWand::MacOsHelperSetup) }
    let(:missing_status)  { build_result(installed: false, valid: false) }

    before do
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return('/fake/helper')
      allow(setup).to receive(:install_helper)
      allow(setup).to receive(:open_location_settings)
    end

    context 'when macOS restores authorization after install' do
      let(:authorized_status) { build_result(authorized: true) }

      before do
        allow(setup).to receive(:check_status)
          .and_return(missing_status, authorized_status)
      end

      it 'calls install_helper' do
        expect(setup).to receive(:install_helper)
        build_cli(setup: setup).run
      end

      it 'does not open Location Services' do
        expect(setup).not_to receive(:open_location_settings)
        build_cli(setup: setup).run
      end

      it 'prints the authorization-preserved message' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('already granted (restored by macOS)')
      end

      it 'returns exit code 0' do
        expect(build_cli(setup: setup).run).to eq(0)
      end
    end

    context 'when authorization is not restored after install' do
      let(:still_unauthorized) { build_result(authorized: false) }

      before do
        allow(setup).to receive(:check_status)
          .and_return(missing_status, still_unauthorized)
        allow(setup).to receive(:open_location_settings)
      end

      it 'opens Location Services' do
        expect(setup).to receive(:open_location_settings)
        build_cli(setup: setup).run
      end

      it 'prints the manual setup instructions' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Manual Setup Instructions')
      end

      it 'returns exit code 0' do
        expect(build_cli(setup: setup).run).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper installed but invalid → reinstall path
  # ---------------------------------------------------------------------------
  describe 'when the helper is invalid (repair recommended)' do
    let(:setup)          { instance_double(WifiWand::MacOsHelperSetup) }
    let(:invalid_status) { build_result(valid: false) }

    before do
      allow(setup).to receive(:reinstall_helper)
      allow(setup).to receive(:open_location_settings)
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive_messages(installed_executable_path: '/fake/helper', installed_bundle_path: '/fake/bundle')
    end

    context 'when macOS preserves authorization after reinstall' do
      let(:authorized_status) { build_result(authorized: true) }

      before do
        allow(setup).to receive(:check_status)
          .and_return(invalid_status, authorized_status)
      end

      it 'calls reinstall_helper (not install_helper)' do
        expect(setup).to receive(:reinstall_helper)
        expect(setup).not_to receive(:install_helper)
        build_cli(setup: setup).run
      end

      it 'does not open Location Services' do
        expect(setup).not_to receive(:open_location_settings)
        build_cli(setup: setup).run
      end

      it 'prints the authorization-preserved message' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('preserved by macOS')
      end

      it 'returns exit code 0' do
        expect(build_cli(setup: setup).run).to eq(0)
      end
    end

    context 'when authorization is not preserved after reinstall' do
      let(:still_unauthorized) { build_result(valid: true, authorized: false) }

      before do
        allow(setup).to receive(:check_status)
          .and_return(invalid_status, still_unauthorized)
      end

      it 'opens Location Services' do
        expect(setup).to receive(:open_location_settings)
        build_cli(setup: setup).run
      end

      it 'shows the reinstall step label in the steps list' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Reinstall wifiwand-helper')
      end

      it 'returns exit code 0' do
        expect(build_cli(setup: setup).run).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper installed, valid, but not authorized → permission step only
  # ---------------------------------------------------------------------------
  describe 'when the helper is valid but not authorized' do
    let(:setup)               { instance_double(WifiWand::MacOsHelperSetup) }
    let(:needs_permission)    { build_result(authorized: false) }

    before do
      allow(setup).to receive(:check_status).and_return(needs_permission)
      allow(setup).to receive(:open_location_settings)
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return('/fake/helper')
    end

    it 'does not call install_helper or reinstall_helper' do
      expect(setup).not_to receive(:install_helper)
      expect(setup).not_to receive(:reinstall_helper)
      build_cli(setup: setup).run
    end

    it 'calls open_location_settings' do
      expect(setup).to receive(:open_location_settings)
      build_cli(setup: setup).run
    end

    it 'renders the Grant permission step label' do
      build_cli(setup: setup).run
      expect(out_stream.string).to include('Grant location permission')
    end

    it 'shows the permission status in the status table' do
      build_cli(setup: setup).run
      expect(out_stream.string).to include('Not authorized')
    end

    it 'returns exit code 0' do
      expect(build_cli(setup: setup).run).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Status table rendering
  # ---------------------------------------------------------------------------
  describe 'status table rendering' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }

    before do
      allow(setup).to receive(:open_location_settings)
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return('/fake/helper')
    end

    it 'shows "repair recommended" when the helper is installed but invalid' do
      invalid = build_result(valid: false)
      allow(setup).to receive(:check_status).and_return(invalid, build_result(authorized: false))
      allow(setup).to receive(:reinstall_helper)
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_bundle_path).and_return('/fake/bundle')

      build_cli(setup: setup).run
      expect(out_stream.string).to include('repair recommended')
    end

    it 'shows "will check after installation" when helper is not installed' do
      missing = build_result(installed: false, valid: false)
      allow(setup).to receive(:check_status).and_return(missing, build_result(authorized: false))
      allow(setup).to receive(:install_helper)

      build_cli(setup: setup).run
      expect(out_stream.string).to include('will check after installation')
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------
  describe 'error handling' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }

    it 'returns exit code 1 when an unexpected error occurs during steps' do
      allow(setup).to receive(:check_status).and_return(build_result(authorized: false))
      allow(setup).to receive(:open_location_settings).and_raise('unexpected failure')
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return('/fake/helper')

      expect(build_cli(setup: setup).run).to eq(1)
    end

    it 'prints the error message' do
      allow(setup).to receive(:check_status).and_return(build_result(authorized: false))
      allow(setup).to receive(:open_location_settings).and_raise('unexpected failure')
      allow(WifiWand::MacOsWifiAuthHelper)
        .to receive(:installed_executable_path).and_return('/fake/helper')

      build_cli(setup: setup).run
      expect(out_stream.string).to include('unexpected failure')
    end
  end
end
