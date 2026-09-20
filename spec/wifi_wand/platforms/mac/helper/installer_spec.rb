# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require_relative '../../../../spec_helper'

RSpec.describe WifiWand::Platforms::Mac::Helper::Installer do
  let(:bundle) { WifiWand::Platforms::Mac::Helper::Bundle }
  let(:temp_dir) { Dir.mktmpdir('wifiwand-installer-spec') }
  let(:helper_timeouts) do
    bundle::TimeoutConfiguration.new(
      default_helper_command_timeout_seconds:       1.0,
      scan_networks_helper_command_timeout_seconds: 2.0,
      helper_termination_wait_seconds:              0.1,
      helper_output_reader_join_seconds:            0.02
    )
  end

  after { FileUtils.rm_rf(temp_dir) }

  describe '.ensure_helper_installed' do
    let(:installed_path) { File.join(temp_dir, 'wifiwand-helper.app') }
    let(:out_stream) { StringIO.new }

    before { allow(bundle).to receive(:installed_bundle_path).and_return(installed_path) }

    it 'returns the installed bundle path without reinstalling when it is already valid' do
      allow(described_class).to receive(:helper_installed_and_valid?).and_return(true)
      allow(described_class).to receive(:install_helper_bundle)

      expect(described_class.ensure_helper_installed(out_stream: out_stream)).to eq(installed_path)
      expect(described_class).not_to have_received(:install_helper_bundle)
    end

    it 'installs the helper and returns its path when the first validation fails' do
      allow(described_class).to receive(:helper_installed_and_valid?).and_return(false, true)
      allow(described_class).to receive(:install_helper_bundle)

      expect(described_class.ensure_helper_installed(out_stream: out_stream)).to eq(installed_path)
      expect(described_class).to have_received(:install_helper_bundle)
        .with(out_stream: out_stream, timeout_configuration: bundle.default_timeout_configuration)
    end

    it 'passes the timeout through to both validations' do
      allow(described_class).to receive(:helper_installed_and_valid?).and_return(false, true)
      allow(described_class).to receive(:install_helper_bundle)

      described_class.ensure_helper_installed(
        out_stream: out_stream, timeout_seconds: 7, timeout_configuration: helper_timeouts
      )

      expect(described_class).to have_received(:helper_installed_and_valid?)
        .with(timeout_seconds: 7, timeout_configuration: helper_timeouts).twice
    end

    it 'raises when the helper still fails validation after installation' do
      allow(described_class).to receive(:helper_installed_and_valid?).and_return(false, false)
      allow(described_class).to receive(:install_helper_bundle)

      expect { described_class.ensure_helper_installed(out_stream: out_stream) }
        .to raise_error(RuntimeError, /failed validation after installation/)
    end
  end

  describe 'install manifest' do
    let(:versioned_dir) { File.join(temp_dir, '9.9.9') }
    let(:manifest_path) { File.join(versioned_dir, bundle::MANIFEST_FILENAME) }

    before do
      FileUtils.mkdir_p(versioned_dir)
      allow(described_class).to receive(:install_manifest_path).and_return(manifest_path)
    end

    describe '.read_install_manifest' do
      it 'returns nil when there is no manifest' do
        expect(described_class.read_install_manifest).to be_nil
      end

      it 'returns nil when the manifest is not valid JSON' do
        File.write(manifest_path, '{ not json')

        expect(described_class.read_install_manifest).to be_nil
      end

      it 'parses a valid manifest' do
        File.write(manifest_path, { 'helper_version' => '9.9.9' }.to_json)

        expect(described_class.read_install_manifest).to eq('helper_version' => '9.9.9')
      end
    end

    describe '.installed_bundle_current?' do
      before do
        allow(bundle).to receive_messages(
          helper_version:        '9.9.9',
          installed_bundle_path: '/installed.app',
          source_bundle_path:    '/source.app'
        )
        allow(bundle).to receive(:bundle_fingerprint).and_return('abc')
      end

      it 'is false when no manifest was written' do
        expect(described_class.installed_bundle_current?).to be(false)
      end

      it 'is true when version and both fingerprints match the manifest' do
        File.write(manifest_path, { 'helper_version' => '9.9.9', 'bundle_fingerprint' => 'abc' }.to_json)

        expect(described_class.installed_bundle_current?).to be(true)
      end

      it 'is false when the manifest records a different helper version' do
        File.write(manifest_path, { 'helper_version' => '1.0.0', 'bundle_fingerprint' => 'abc' }.to_json)

        expect(described_class.installed_bundle_current?).to be(false)
      end

      it 'is false when the source bundle no longer matches the recorded fingerprint' do
        File.write(manifest_path, { 'helper_version' => '9.9.9', 'bundle_fingerprint' => 'abc' }.to_json)
        allow(bundle).to receive(:bundle_fingerprint) { |path| path == '/source.app' ? 'changed' : 'abc' }

        expect(described_class.installed_bundle_current?).to be(false)
      end
    end
  end

  describe '.run_bounded_helper_command' do
    it 'returns nil when the helper executable does not exist' do
      missing = File.join(temp_dir, 'no-such-helper')

      result = described_class.run_bounded_helper_command(
        missing, 'help', timeout_configuration: helper_timeouts
      )

      expect(result).to be_nil
    end
  end

  describe '.finalize_helper_output_reader' do
    it 'does nothing when there is no reader' do
      stream = instance_double(IO)
      allow(stream).to receive(:close)

      described_class.finalize_helper_output_reader(nil, stream, timeout_configuration: helper_timeouts)

      expect(stream).not_to have_received(:close)
    end

    it 'still joins the reader when closing the stream raises IOError' do
      stream = instance_double(IO, closed?: false)
      allow(stream).to receive(:close).and_raise(IOError, 'stream gone')
      reader = instance_double(Thread, join: nil)

      expect do
        described_class.finalize_helper_output_reader(reader, stream, timeout_configuration: helper_timeouts)
      end.not_to raise_error
      expect(reader).to have_received(:join).with(helper_timeouts.helper_output_reader_join_seconds)
    end
  end

  describe '.terminate_helper_process' do
    let(:wait_thread) { instance_double(Process::Waiter, pid: 4242) }

    it 'ignores a helper process that has already gone away' do
      allow(Process).to receive(:kill).with('TERM', 4242).and_raise(Errno::ESRCH)

      expect(described_class.terminate_helper_process(wait_thread, timeout_configuration: helper_timeouts))
        .to be_nil
    end

    it 'ignores a helper process that is not our child' do
      allow(Process).to receive(:kill).with('TERM', 4242).and_raise(Errno::ECHILD)

      expect(described_class.terminate_helper_process(wait_thread, timeout_configuration: helper_timeouts))
        .to be_nil
    end

    it 'escalates to KILL when the helper ignores TERM' do
      allow(Process).to receive(:kill)
      allow(wait_thread).to receive_messages(alive?: true, join: nil)

      described_class.terminate_helper_process(wait_thread, timeout_configuration: helper_timeouts)

      expect(Process).to have_received(:kill).with('TERM', 4242).ordered
      expect(Process).to have_received(:kill).with('KILL', 4242).ordered
    end

    it 'does not send KILL once the helper exits after TERM' do
      allow(Process).to receive(:kill)
      allow(wait_thread).to receive(:join).and_return(wait_thread)

      described_class.terminate_helper_process(wait_thread, timeout_configuration: helper_timeouts)

      expect(Process).to have_received(:kill).with('TERM', 4242)
      expect(Process).not_to have_received(:kill).with('KILL', 4242)
    end
  end

  describe '.resolved_legacy_release_target' do
    let(:versioned_dir) { File.join(temp_dir, '9.9.9') }
    let(:executable_path) { File.join(versioned_dir, 'wifiwand-helper.app', 'Contents', 'MacOS', 'helper') }

    before do
      FileUtils.mkdir_p(File.dirname(executable_path))
      allow(bundle).to receive_messages(
        installed_executable_path: executable_path,
        versioned_install_dir:     versioned_dir
      )
    end

    it 'is nil when the installed executable is a regular file' do
      File.write(executable_path, '#!/bin/sh')

      expect(described_class.resolved_legacy_release_target).to be_nil
    end

    it 'resolves an absolute symlink to the release bundle directory' do
      release_bundle = File.join(versioned_dir, 'releases', 'r1')
      FileUtils.rm_f(executable_path)
      File.symlink(File.join(release_bundle, 'Contents', 'MacOS', 'helper'), executable_path)

      expect(described_class.resolved_legacy_release_target).to eq(release_bundle)
    end

    it 'resolves a relative symlink against the versioned install directory' do
      FileUtils.rm_f(executable_path)
      File.symlink('releases/r1/Contents/MacOS/helper', executable_path)

      expect(described_class.resolved_legacy_release_target)
        .to eq(File.join(versioned_dir, 'releases', 'r1'))
    end
  end
end
