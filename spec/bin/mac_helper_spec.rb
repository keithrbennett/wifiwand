# frozen_string_literal: true

require_relative '../spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
load File.expand_path('../../bin/mac-helper', __dir__)

MAC_HELPER_PATH = File.expand_path('../../bin/mac-helper', __dir__)
MAC_HELPER_DEFAULT_ENV_FILE = File.expand_path('../../.env.release', __dir__)

RSpec.describe 'bin/mac-helper' do
  def make_fake_command(path, body)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def run_mac_helper(argv:, chdir:, command_path: MAC_HELPER_PATH, env: {})
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, command_path, *argv, chdir:)
    { stdout:, stderr:, exit_code: status.exitstatus }
  end

  def find_executable(command)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
      path = File.join(dir, command)
      return path if File.file?(path) && File.executable?(path)
    end

    raise "Unable to find #{command} in PATH"
  end

  def with_fake_path_dir
    Dir.mktmpdir do |tmpdir|
      fake_path_dir = File.join(tmpdir, 'path-bin')
      FileUtils.mkdir_p(fake_path_dir)
      FileUtils.ln_s(find_executable('git'), File.join(fake_path_dir, 'git'))
      yield tmpdir, fake_path_dir
    end
  end

  def expect_op_wrap_exec(result, command_path:)
    expect(result[:exit_code]).to eq(0)
    expect(result[:stderr]).to eq('')
    expect(result[:stdout]).to include('run')
    expect(result[:stdout]).to include("--env-file=#{MAC_HELPER_DEFAULT_ENV_FILE}")
    expect(result[:stdout]).to include('--')
    expect(result[:stdout]).to include(command_path)
    expect(result[:stdout]).to include('notarize')
  end


  describe MacHelperCLI::CLI do
    def build_cli(argv)
      described_class.new(argv)
    end

    def stub_release_selection(cli)
      allow(cli).to receive(:has_credentials?).and_return(true)
      allow(WifiWand::MacHelperRelease).to receive(:normalize_submission_order) { |order| order }
    end

    it 'defaults cancel to the oldest pending submission' do
      cli = build_cli(['cancel'])
      stub_release_selection(cli)

      expect(WifiWand::MacHelperRelease).to receive(:select_submission_id)
        .with(order: :asc, pending_only: true)
        .and_return('pending-001')
      expect(WifiWand::MacHelperRelease).to receive(:cancel_notarization).with('pending-001')

      expect { cli.run }
        .to output(/using oldest pending notary submission pending-001/).to_stdout
    end

    it 'defaults info to the latest submission' do
      cli = build_cli(['info'])
      stub_release_selection(cli)

      expect(WifiWand::MacHelperRelease).to receive(:select_submission_id)
        .with(order: :desc, pending_only: false)
        .and_return('latest-001')
      expect(WifiWand::MacHelperRelease).to receive(:notarization_status).with('latest-001')

      expect { cli.run }
        .to output(/using latest notary submission latest-001/).to_stdout
    end

    it 'defaults log to the latest submission' do
      cli = build_cli(['log'])
      stub_release_selection(cli)

      expect(WifiWand::MacHelperRelease).to receive(:select_submission_id)
        .with(order: :desc, pending_only: false)
        .and_return('latest-002')
      expect(WifiWand::MacHelperRelease).to receive(:notarization_log).with('latest-002')

      expect { cli.run }
        .to output(/using latest notary submission latest-002/).to_stdout
    end

    it 'lets an explicit order flag override cancel ordering without clearing pending_only' do
      cli = build_cli(['cancel', '--order', 'desc'])
      stub_release_selection(cli)

      expect(WifiWand::MacHelperRelease).to receive(:select_submission_id)
        .with(order: :desc, pending_only: true)
        .and_return('pending-override')
      expect(WifiWand::MacHelperRelease).to receive(:cancel_notarization).with('pending-override')

      expect { cli.run }
        .to output(/using latest pending notary submission pending-override/).to_stdout
    end

    it 'lets an explicit pending-only flag override info selection' do
      cli = build_cli(['info', '--pending-only'])
      stub_release_selection(cli)

      expect(WifiWand::MacHelperRelease).to receive(:select_submission_id)
        .with(order: :desc, pending_only: true)
        .and_return('latest-pending')
      expect(WifiWand::MacHelperRelease).to receive(:notarization_status).with('latest-pending')

      expect { cli.run }
        .to output(/using latest pending notary submission latest-pending/).to_stdout
    end
  end

  it 'finds op-wrap relative to the real script and re-execs with the current Ruby outside the repo root' do
    with_fake_path_dir do |tmpdir, fake_path_dir|
      fake_op = File.join(tmpdir, 'fake-op')
      make_fake_command(fake_op, <<~SH)
        #!/bin/sh
        printf '%s\n' "$@"
      SH

      result = run_mac_helper(
        env:   {
          'PATH'            => fake_path_dir,
          'WIFIWAND_OP_BIN' => fake_op,
        },
        argv:  ['notarize'],
        chdir: tmpdir
      )

      expect_op_wrap_exec(result, command_path: MAC_HELPER_PATH)
    end
  end

  it 'finds op-wrap relative to the real script when launched via symlink' do
    with_fake_path_dir do |tmpdir, fake_path_dir|
      fake_op = File.join(tmpdir, 'fake-op')
      symlink_path = File.join(tmpdir, 'mac-helper')
      FileUtils.ln_s(MAC_HELPER_PATH, symlink_path)
      make_fake_command(fake_op, <<~SH)
        #!/bin/sh
        printf '%s\n' "$@"
      SH

      result = run_mac_helper(
        command_path: symlink_path,
        env:          {
          'PATH'            => fake_path_dir,
          'WIFIWAND_OP_BIN' => fake_op,
        },
        argv:         ['notarize'],
        chdir:        tmpdir
      )

      expect_op_wrap_exec(result, command_path: symlink_path)
    end
  end
end
