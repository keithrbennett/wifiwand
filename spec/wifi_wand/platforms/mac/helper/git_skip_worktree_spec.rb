# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../../../spec_helper'
require_relative '../../../../../lib/wifi_wand/platforms/mac/helper/git_skip_worktree'

describe WifiWand::Platforms::Mac::Helper::GitSkipWorktree do
  let(:repo_root) { Dir.mktmpdir('wifiwand-helper-skip-spec') }
  let(:out_stream) { StringIO.new }
  let(:helper) { described_class.new(repo_root: repo_root, out_stream: out_stream) }
  let(:helper_binary_path) do
    File.join(repo_root, 'libexec', 'macos', 'wifiwand-helper.app', 'Contents', 'MacOS',
      'wifiwand-helper')
  end
  let(:root_code_resources_path) do
    File.join(repo_root, 'libexec', 'macos', 'wifiwand-helper.app', 'Contents', 'CodeResources')
  end
  let(:signature_code_resources_path) do
    File.join(repo_root, 'libexec', 'macos', 'wifiwand-helper.app', 'Contents', '_CodeSignature',
      'CodeResources')
  end
  let(:info_plist_path) do
    File.join(repo_root, 'libexec', 'macos', 'wifiwand-helper.app', 'Contents', 'Info.plist')
  end
  let(:manifest_path) do
    File.join(repo_root, 'libexec', 'macos', 'wifiwand-helper.source-manifest.json')
  end
  let(:source_path) do
    File.join(repo_root, 'libexec', 'macos', 'src', 'wifiwand-helper.swift')
  end

  before do
    run_git('init')
    write_file(helper_binary_path, "#!/bin/sh\necho helper\n")
    write_file(root_code_resources_path, "root signature metadata\n")
    write_file(signature_code_resources_path, "signature metadata\n")
    write_file(info_plist_path, "<plist version=\"1.0\"><dict /></plist>\n")
    write_file(manifest_path, "{}\n")
    write_file(source_path, "print(\"source\")\n")
    run_git('add', 'libexec/macos')
  end

  after do
    FileUtils.rm_rf(repo_root)
  end

  it 'marks generated helper artifact files as skipped without skipping source or template files' do
    result = helper.start

    expect(result).to be_skipped
    expect(skipped_paths).to contain_exactly(
      'libexec/macos/wifiwand-helper.app/Contents/CodeResources',
      'libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper',
      'libexec/macos/wifiwand-helper.app/Contents/_CodeSignature/CodeResources',
      'libexec/macos/wifiwand-helper.source-manifest.json'
    )
    expect(skipped_paths).not_to include('libexec/macos/src/wifiwand-helper.swift')
    expect(skipped_paths).not_to include('libexec/macos/wifiwand-helper.app/Contents/Info.plist')
    expect(out_stream.string).to include('Started helper artifact skip-worktree: 4/4 tracked files skipped')
  end

  it 'clears skip-worktree from generated helper artifact files' do
    helper.start

    result = helper.stop

    expect(result.skipped_count).to eq(0)
    expect(skipped_paths).to be_empty
    expect(out_stream.string).to include('Stopped helper artifact skip-worktree: 0/4 tracked files skipped')
  end

  it 'prints current skip-worktree status' do
    helper.start
    out_stream.truncate(0)
    out_stream.rewind

    result = helper.print_status

    expect(result).to be_skipped
    expect(out_stream.string).to include('Helper artifact skip-worktree status: 4/4 tracked files skipped')
  end

  it 'raises a skip-worktree-specific error when Git fails' do
    allow(Open3).to receive(:capture3)
      .with('git', 'ls-files', '-v', '--', *described_class::DEFAULT_PATHS, any_args)
      .and_return(['', 'fatal: not a git repository', failure_status])

    expect { helper.status }
      .to raise_error(described_class::Error, /git ls-files .* fatal: not a git repository/)
  end

  def skipped_paths
    run_git('ls-files', '-v', '--', 'libexec/macos')
      .lines
      .grep(/\AS /)
      .map { |line| line.delete_prefix('S ').strip }
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def run_git(*args)
    stdout, stderr, status = Open3.capture3('git', *args, chdir: repo_root)
    raise "git #{args.join(' ')} failed: #{stderr.empty? ? stdout : stderr}" unless status.success?

    stdout
  end

  def failure_status = instance_double(Process::Status, success?: false)
end
