# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'wifi-wand/mac_helper/mac_os_setup_cli'

RSpec.describe WifiWand::MacOsSetupCli do
  before do
    allow(WifiWand::MacOsHelperBundle).to receive(:helper_install_dir_count).and_return(0)
  end

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

  def build_support_status(version)
    WifiWand::MacOsHelperSetup::SupportStatus.new(
      macos_version:  version,
      parsed_version: WifiWand::MacOsHelperBundle.parse_macos_version(version)
    )
  end

  def supported_helper_status = build_support_status('14.0')

  def build_cli(argv: [], setup: nil, support_status: supported_helper_status)
    allow(setup).to receive(:helper_support_status).and_return(support_status) if setup

    cli = described_class.new(
      argv:       argv,
      setup:      setup,
      out_stream: out_stream,
      in_stream:  in_stream
    )
    allow(cli).to receive(:sleep)
    cli
  end

  # Shared setup mock that stubs the parts every scenario touches.
  def stub_setup(setup, initial_status:, post_status: nil)
    allow(setup).to receive(:check_status).and_return(initial_status, *(post_status ? [post_status] : []))
    allow(setup).to receive(:install_helper)
    allow(setup).to receive(:reinstall_helper)
    allow(setup).to receive(:remove_helper)
    allow(setup).to receive(:open_location_settings).and_return(true)
    allow(WifiWand::MacOsHelperBundle)
      .to receive_messages(installed_executable_path: '/fake/helper', installed_bundle_path: '/fake/bundle')
  end

  # ---------------------------------------------------------------------------
  # macOS version applicability
  # ---------------------------------------------------------------------------
  describe 'when macOS is older than the helper minimum' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }
    let(:support_status) { build_support_status('13.6.1') }

    before do
      allow(setup).to receive(:check_status)
      allow(setup).to receive(:install_helper)
      allow(setup).to receive(:reinstall_helper)
      allow(setup).to receive(:remove_helper)
      allow(setup).to receive(:open_location_settings).and_return(true)
    end

    it 'returns exit code 0' do
      expect(build_cli(setup: setup, support_status: support_status).run).to eq(0)
    end

    it 'prints a not-applicable message with fallback behavior' do
      build_cli(setup: setup, support_status: support_status).run
      expect(out_stream.string).to include('not applicable')
      expect(out_stream.string).to include('only used on macOS 14.0+')
      expect(out_stream.string).to include('fallback WiFi paths')
    end

    it 'does not prompt for ENTER or show Location Services instructions' do
      build_cli(setup: setup, support_status: support_status).run
      expect(out_stream.string).not_to include('Press ENTER')
      expect(out_stream.string).not_to include('Manual Setup Instructions')
    end

    it 'does not install, reinstall, or open Location Services' do
      build_cli(setup: setup, support_status: support_status).run
      expect(setup).not_to have_received(:install_helper)
      expect(setup).not_to have_received(:reinstall_helper)
      expect(setup).not_to have_received(:open_location_settings)
    end

    it 'treats --reinstall as the same no-op exit 0' do
      expect(build_cli(argv: ['--reinstall'], setup: setup, support_status: support_status).run).to eq(0)
      expect(setup).not_to have_received(:reinstall_helper)
      expect(out_stream.string).to include('not applicable')
    end

    it 'still allows --remove to remove installed files' do
      allow(setup).to receive(:remove_helper).and_return('/fake/install-dir')

      expect(build_cli(argv: ['--remove'], setup: setup, support_status: support_status).run).to eq(0)
      expect(setup).to have_received(:remove_helper)
      expect(out_stream.string).to include('Removed wifiwand-helper installation')
    end
  end

  describe 'when macOS support cannot be detected' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }
    let(:missing_status) { build_result(installed: false, valid: false) }

    before do
      allow(setup).to receive(:check_status).and_return(missing_status, build_result(authorized: false))
      allow(setup).to receive(:install_helper)
      allow(setup).to receive(:open_location_settings).and_return(true)
      allow(WifiWand::MacOsHelperBundle)
        .to receive_messages(installed_executable_path: '/fake/helper', installed_bundle_path: '/fake/bundle')
    end

    it 'preserves the existing setup path for missing versions' do
      build_cli(setup: setup, support_status: build_support_status(nil)).run
      expect(setup).to have_received(:install_helper)
      expect(out_stream.string).to include('Press ENTER')
    end

    it 'preserves the existing setup path for malformed versions' do
      build_cli(setup: setup, support_status: build_support_status('developer seed')).run
      expect(setup).to have_received(:install_helper)
      expect(out_stream.string).to include('Press ENTER')
    end
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

    it 'does not call helper lifecycle operations' do
      expect(setup).not_to receive(:install_helper)
      expect(setup).not_to receive(:reinstall_helper)
      expect(setup).not_to receive(:remove_helper)
      build_cli(setup: setup).run
    end
  end

  # ---------------------------------------------------------------------------
  # --reinstall flag
  # ---------------------------------------------------------------------------
  describe '--reinstall flag' do
    let(:setup)          { instance_double(WifiWand::MacOsHelperSetup) }
    let(:complete_status) { build_result(authorized: true) }

    context 'when reinstall succeeds' do
      before do
        allow(setup).to receive(:reinstall_helper)
        stub_setup(setup, initial_status: complete_status)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:installed_bundle_path).and_return('/fake/bundle')
      end

      it 'calls reinstall_helper before the normal status check' do
        expect(setup).to receive(:reinstall_helper).ordered
        expect(setup).to receive(:check_status).and_return(complete_status).ordered
        build_cli(argv: ['--reinstall'], setup: setup).run
      end

      it 'prints a reinstall confirmation message' do
        build_cli(argv: ['--reinstall'], setup: setup).run
        expect(out_stream.string).to include('Reinstalling')
        expect(out_stream.string).to include('reinstalled at:')
      end

      it 'returns exit code 0 when the post-reinstall status is complete' do
        expect(build_cli(argv: ['--reinstall'], setup: setup).run).to eq(0)
      end
    end

    context 'when reinstall_helper raises an error' do
      before do
        allow(setup).to receive(:reinstall_helper).and_raise('bundle copy failed')
        allow(setup).to receive(:check_status).and_return(complete_status)
        allow(WifiWand::MacOsHelperBundle)
          .to receive(:installed_bundle_path).and_return('/fake/bundle')
      end

      it 'returns exit code 1' do
        expect(build_cli(argv: ['--reinstall'], setup: setup).run).to eq(1)
      end

      it 'prints the error message' do
        build_cli(argv: ['--reinstall'], setup: setup).run
        expect(out_stream.string).to include('bundle copy failed')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # --remove flag
  # ---------------------------------------------------------------------------
  describe '--remove flag' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }

    before do
      allow(setup).to receive(:remove_helper).and_return('/fake/install-dir')
    end

    it 'removes the helper installation' do
      expect(setup).to receive(:remove_helper).and_return('/fake/install-dir')
      build_cli(argv: ['--remove'], setup: setup).run
    end

    it 'does not run setup status checks' do
      expect(setup).not_to receive(:check_status)
      build_cli(argv: ['--remove'], setup: setup).run
    end

    it 'does not open Location Services' do
      expect(setup).not_to receive(:open_location_settings)
      build_cli(argv: ['--remove'], setup: setup).run
    end

    it 'prints revocation guidance' do
      build_cli(argv: ['--remove'], setup: setup).run
      expect(out_stream.string).to include('Removed wifiwand-helper installation at: /fake/install-dir')
      expect(out_stream.string).to include('Location Services permission is managed by macOS')
    end

    it 'returns exit code 0' do
      expect(build_cli(argv: ['--remove'], setup: setup).run).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Helper version directory notice
  # ---------------------------------------------------------------------------
  describe 'helper version directory notice' do
    let(:setup)          { instance_double(WifiWand::MacOsHelperSetup) }
    let(:missing_status) { build_result(installed: false, valid: false) }
    let(:complete_status) { build_result(authorized: true) }

    before do
      allow(WifiWand::MacOsHelperBundle).to receive_messages(
        helper_install_dir_count: 6,
        helper_version:           '3.0.0',
        installed_bundle_path:    '/fake/bundle'
      )
      allow(setup).to receive(:install_helper)
      allow(setup).to receive(:reinstall_helper)
      allow(setup).to receive(:open_location_settings).and_return(true)
    end

    it 'prints an advisory notice after installing when helper version directories exceed the threshold' do
      allow(setup).to receive(:check_status).and_return(missing_status, complete_status)

      build_cli(setup: setup).run
      expect(out_stream.string).to include('WifiWand found 6 helper version directories')
      expect(out_stream.string).to include(WifiWand::MacOsHelperBundle::INSTALL_PARENT)
      expect(out_stream.string).to include('Keep the current version directory: 3.0.0')
    end

    it 'prints an advisory notice after explicit reinstall when directories exceed the threshold' do
      allow(setup).to receive(:check_status).and_return(complete_status)

      build_cli(argv: ['--reinstall'], setup: setup).run
      expect(out_stream.string).to include('WifiWand found 6 helper version directories')
      expect(out_stream.string).to include('Older helper versions are not used')
    end

    it 'does not print the notice when the directory count is at the threshold' do
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:helper_install_dir_count)
        .and_return(WifiWand::MacOsHelperBundle::VERSION_DIRECTORY_NOTICE_THRESHOLD)
      allow(setup).to receive(:check_status).and_return(missing_status, complete_status)

      build_cli(setup: setup).run
      expect(out_stream.string).not_to include('helper version directories')
    end

    it 'does not print the notice when setup is already complete' do
      allow(setup).to receive(:check_status).and_return(complete_status)

      build_cli(setup: setup).run
      expect(out_stream.string).not_to include('helper version directories')
    end
  end

  # ---------------------------------------------------------------------------
  # Helper not installed → install path
  # ---------------------------------------------------------------------------
  describe 'when the helper is not installed' do
    let(:setup)           { instance_double(WifiWand::MacOsHelperSetup) }
    let(:missing_status)  { build_result(installed: false, valid: false) }

    before do
      allow(WifiWand::MacOsHelperBundle)
        .to receive_messages(installed_executable_path: '/fake/helper', installed_bundle_path: '/fake/bundle')
      allow(setup).to receive(:install_helper)
      allow(setup).to receive(:open_location_settings).and_return(true)
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

      it 'prints the helper app bundle path instead of the internal executable path' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Helper installed at: /fake/bundle')
        expect(out_stream.string).not_to include('Helper installed at: /fake/helper')
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
        allow(setup).to receive(:open_location_settings).and_return(true)
      end

      it 'opens Location Services' do
        expect(setup).to receive(:open_location_settings).and_return(true)
        build_cli(setup: setup).run
      end

      it 'prints the manual setup instructions' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Manual Setup Instructions')
      end

      it 'prints the helper app bundle path instead of the internal executable path' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Helper installed at: /fake/bundle')
        expect(out_stream.string).not_to include('Helper installed at: /fake/helper')
      end

      it 'returns exit code 0' do
        expect(build_cli(setup: setup).run).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper installed but invalid → reinstall path
  # ---------------------------------------------------------------------------
  describe 'when the helper is invalid (reinstall recommended)' do
    let(:setup)          { instance_double(WifiWand::MacOsHelperSetup) }
    let(:invalid_status) { build_result(valid: false) }

    before do
      allow(setup).to receive(:reinstall_helper)
      allow(setup).to receive(:open_location_settings).and_return(true)
      allow(WifiWand::MacOsHelperBundle)
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

      it 'prints the helper app bundle path instead of the internal executable path' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Helper reinstalled at: /fake/bundle')
        expect(out_stream.string).not_to include('Helper reinstalled at: /fake/helper')
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
        expect(setup).to receive(:open_location_settings).and_return(true)
        build_cli(setup: setup).run
      end

      it 'shows the reinstall step label in the steps list' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Reinstall wifiwand-helper')
      end

      it 'prints the helper app bundle path instead of the internal executable path' do
        build_cli(setup: setup).run
        expect(out_stream.string).to include('Helper reinstalled at: /fake/bundle')
        expect(out_stream.string).not_to include('Helper reinstalled at: /fake/helper')
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
      allow(setup).to receive_messages(
        check_status:           needs_permission,
        open_location_settings: true
      )
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_executable_path).and_return('/fake/helper')
    end

    it 'does not call install_helper or reinstall_helper' do
      expect(setup).not_to receive(:install_helper)
      expect(setup).not_to receive(:reinstall_helper)
      build_cli(setup: setup).run
    end

    it 'calls open_location_settings' do
      expect(setup).to receive(:open_location_settings).and_return(true)
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

    it 'returns exit code 1 when Location Services does not open automatically' do
      allow(setup).to receive(:open_location_settings).and_return(false)

      expect(build_cli(setup: setup).run).to eq(1)
    end

    it 'keeps manual instructions visible when Location Services does not open automatically' do
      allow(setup).to receive(:open_location_settings).and_return(false)

      build_cli(setup: setup).run
      expect(out_stream.string).to include('Manual Setup Instructions')
      expect(out_stream.string).to include('System Settings did not open automatically')
      expect(out_stream.string).to include('Could not open macOS Location Services settings automatically')
    end
  end

  # ---------------------------------------------------------------------------
  # Status table rendering
  # ---------------------------------------------------------------------------
  describe 'status table rendering' do
    let(:setup) { instance_double(WifiWand::MacOsHelperSetup) }

    before do
      allow(setup).to receive(:open_location_settings).and_return(true)
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_executable_path).and_return('/fake/helper')
    end

    it 'shows "reinstall recommended" when the helper is installed but invalid' do
      invalid = build_result(valid: false)
      allow(setup).to receive(:check_status).and_return(invalid, build_result(authorized: false))
      allow(setup).to receive(:reinstall_helper)
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_bundle_path).and_return('/fake/bundle')

      build_cli(setup: setup).run
      expect(out_stream.string).to include('reinstall recommended')
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

    it 'returns exit code 1 for the removed --repair option' do
      expect(build_cli(argv: ['--repair'], setup: setup).run).to eq(1)
    end

    it 'prints an invalid option error for the removed --repair option' do
      build_cli(argv: ['--repair'], setup: setup).run
      expect(out_stream.string).to include('invalid option: --repair')
    end

    it 'returns exit code 1 when reinstall and remove are both requested' do
      expect(build_cli(argv: %w[--reinstall --remove], setup: setup).run).to eq(1)
    end

    it 'prints the mutual-exclusion error when reinstall and remove are both requested' do
      build_cli(argv: %w[--reinstall --remove], setup: setup).run
      expect(out_stream.string).to include('choose only one of --reinstall or --remove')
    end

    it 'returns exit code 1 when positional arguments are provided' do
      expect(setup).not_to receive(:check_status)

      expect(build_cli(argv: ['ignored'], setup: setup).run).to eq(1)
    end

    it 'prints usage when positional arguments are provided' do
      build_cli(argv: ['ignored'], setup: setup).run

      expect(out_stream.string).to include('Unexpected argument(s): ignored')
      expect(out_stream.string).to include('Usage: wifi-wand-macos-setup [--reinstall | --remove]')
    end

    it 'does not remove the helper when --remove receives a positional argument' do
      expect(setup).not_to receive(:remove_helper)

      build_cli(argv: %w[--remove ignored], setup: setup).run
    end

    it 'does not reinstall the helper when --reinstall receives a positional argument' do
      expect(setup).not_to receive(:reinstall_helper)

      build_cli(argv: %w[--reinstall ignored], setup: setup).run
    end

    it 'returns exit code 1 when the Location Services opener raises an error' do
      allow(setup).to receive(:check_status).and_return(build_result(authorized: false))
      allow(setup).to receive(:open_location_settings).and_raise('unexpected failure')
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_executable_path).and_return('/fake/helper')

      expect(build_cli(setup: setup).run).to eq(1)
    end

    it 'prints manual instructions and the opener error message' do
      allow(setup).to receive(:check_status).and_return(build_result(authorized: false))
      allow(setup).to receive(:open_location_settings).and_raise('unexpected failure')
      allow(WifiWand::MacOsHelperBundle)
        .to receive(:installed_executable_path).and_return('/fake/helper')

      build_cli(setup: setup).run
      expect(out_stream.string).to include('Manual Setup Instructions')
      expect(out_stream.string).to include('System Settings did not open automatically')
      expect(out_stream.string).to include('unexpected failure')
    end
  end
end
