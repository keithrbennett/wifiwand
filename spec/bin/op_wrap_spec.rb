# frozen_string_literal: true

require_relative '../spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tempfile'
require 'tmpdir'

# Load the helper methods from bin/op-wrap without triggering main execution.
# The __FILE__ == $PROGRAM_NAME guard in the script ensures only the method
# definitions are evaluated when the file is loaded via `load`.
load File.expand_path('../../bin/op-wrap', __dir__)

OP_WRAP_PATH = File.expand_path('../../bin/op-wrap', __dir__)
OP_WRAP_DEFAULT_ENV_FILE = File.expand_path('../../.env.release', __dir__)

RSpec.describe 'bin/op-wrap' do
  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [k, ENV[k]] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end

  def with_fake_op_in_tmpdir(name: 'op')
    dir = Dir.mktmpdir
    path = File.join(dir, name)
    FileUtils.touch(path)
    File.chmod(0o755, path)
    yield dir, path
  ensure
    FileUtils.rm_rf(dir)
  end

  def make_fake_command(path, body)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def run_op_wrap(command_path: OP_WRAP_PATH, env: {}, argv: [], chdir: nil)
    command = [env, RbConfig.ruby, command_path, *argv]
    options = chdir ? { chdir: chdir } : {}
    stdout, stderr, status = Open3.capture3(*command, **options)
    { stdout:, stderr:, exit_code: status.exitstatus }
  end

  describe '#op_executable?' do
    context 'when op_bin is a bare name (no path separator)' do
      it 'returns true when an executable regular file named op is found in PATH' do
        with_fake_op_in_tmpdir do |dir, _|
          with_env('PATH' => dir) do
            expect(op_executable?('op')).to be true
          end
        end
      end

      it 'returns false when the binary is not found in PATH' do
        with_env('PATH' => Dir.mktmpdir) do
          expect(op_executable?('op')).to be false
        end
      end

      it 'returns false for an executable directory named op in PATH' do
        dir = Dir.mktmpdir
        subdir = File.join(dir, 'op')
        Dir.mkdir(subdir)
        File.chmod(0o755, subdir)
        with_env('PATH' => dir) do
          expect(op_executable?('op')).to be false
        end
      ensure
        FileUtils.rm_rf(dir)
      end

      it 'treats shell metacharacters as a literal filename, not shell code' do
        sentinel = '/tmp/op_wrap_injection_test'
        FileUtils.rm_f(sentinel)

        with_env('PATH' => Dir.mktmpdir) do
          result = op_executable?('op; touch /tmp/op_wrap_injection_test')
          expect(result).to be false
        end

        expect(File.exist?(sentinel)).to be false
      end

      it 'treats pipe metacharacters as a literal filename' do
        with_env('PATH' => Dir.mktmpdir) do
          expect(op_executable?('op | cat')).to be false
        end
      end

      it 'treats backtick metacharacters as a literal filename' do
        with_env('PATH' => Dir.mktmpdir) do
          expect(op_executable?('`id`')).to be false
        end
      end
    end

    context 'when op_bin contains a path separator (absolute or relative path)' do
      it 'returns true for an existing executable regular file' do
        Tempfile.create('op') do |f|
          File.chmod(0o755, f.path)
          expect(op_executable?(f.path)).to be true
        end
      end

      it 'returns false for a non-existent path' do
        expect(op_executable?('/nonexistent/path/op')).to be false
      end

      it 'returns false for an existing but non-executable file' do
        Tempfile.create('op') do |f|
          File.chmod(0o644, f.path)
          expect(op_executable?(f.path)).to be false
        end
      end

      it 'returns false for an executable directory (e.g. WIFIWAND_OP_BIN=/bin)' do
        expect(op_executable?('/bin')).to be false
      end

      it 'treats a path with semicolon metacharacters as a literal path' do
        sentinel = '/tmp/op_wrap_path_injection_test'
        FileUtils.rm_f(sentinel)

        result = op_executable?('/nonexistent/op; touch /tmp/op_wrap_path_injection_test')
        expect(result).to be false
        expect(File.exist?(sentinel)).to be false
      end
    end
  end

  describe '#check_op_available!' do
    it 'does not exit when op_bin resolves to an executable file' do
      with_fake_op_in_tmpdir do |_, path|
        expect { check_op_available!(path) }.not_to raise_error
      end
    end

    it 'exits with code 1 when op_bin is not found' do
      expect { check_op_available!('/nonexistent/op') }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(1)
      end
    end

    it 'prints an error message to stderr when op_bin is not found' do
      expect do
        check_op_available!('/nonexistent/op')
      rescue SystemExit
        # expected; we only care about the stderr content
      end.to output(/not found in PATH/).to_stderr
    end
  end

  describe '#show_usage_and_exit' do
    it 'exits with code 64' do
      expect { show_usage_and_exit }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(64)
      end
    end

    it 'prints usage information to stderr' do
      expect do
        show_usage_and_exit
      rescue SystemExit
        # expected
      end.to output(/Usage:/).to_stderr
    end
  end

  describe '#default_env_file' do
    it 'resolves .env.release relative to the real script path' do
      expect(default_env_file).to eq(OP_WRAP_DEFAULT_ENV_FILE)
    end
  end

  describe 'main execution (subprocess)' do
    it 'exits 1 with an error message when op_bin does not exist' do
      result = run_op_wrap(env: { 'WIFIWAND_OP_BIN' => '/nonexistent/op' })
      expect(result[:exit_code]).to eq(1)
      expect(result[:stderr]).to match(/not found in PATH/)
    end

    it 'exits 64 with usage text when op is found but no arguments are given' do
      with_fake_op_in_tmpdir do |_, path|
        result = run_op_wrap(env: { 'WIFIWAND_OP_BIN' => path }, argv: [])
        expect(result[:exit_code]).to eq(64)
        expect(result[:stderr]).to match(/Usage:/)
      end
    end

    it 'uses the repo-relative default env file when launched outside the repo root' do
      Dir.mktmpdir do |tmpdir|
        fake_op = File.join(tmpdir, 'fake-op')
        make_fake_command(fake_op, <<~SH)
          #!/bin/sh
          printf '%s\n' "$@"
        SH

        result = run_op_wrap(
          env:   { 'WIFIWAND_OP_BIN' => fake_op },
          argv:  %w[echo hello],
          chdir: tmpdir
        )

        expect(result[:exit_code]).to eq(0)
        expect(result[:stderr]).to eq('')
        expect(result[:stdout]).to include('run')
        expect(result[:stdout]).to include("--env-file=#{OP_WRAP_DEFAULT_ENV_FILE}")
        expect(result[:stdout]).to include('--')
        expect(result[:stdout]).to include('echo')
        expect(result[:stdout]).to include('hello')
      end
    end

    it 'uses the repo-relative default env file when launched via symlink' do
      Dir.mktmpdir do |tmpdir|
        fake_op = File.join(tmpdir, 'fake-op')
        symlink_path = File.join(tmpdir, 'op-wrap')
        FileUtils.ln_s(OP_WRAP_PATH, symlink_path)
        make_fake_command(fake_op, <<~SH)
          #!/bin/sh
          printf '%s\n' "$@"
        SH

        result = run_op_wrap(
          command_path: symlink_path,
          env:          { 'WIFIWAND_OP_BIN' => fake_op },
          argv:         %w[echo hello],
          chdir:        tmpdir
        )

        expect(result[:exit_code]).to eq(0)
        expect(result[:stderr]).to eq('')
        expect(result[:stdout]).to include('run')
        expect(result[:stdout]).to include("--env-file=#{OP_WRAP_DEFAULT_ENV_FILE}")
        expect(result[:stdout]).to include('--')
        expect(result[:stdout]).to include('echo')
        expect(result[:stdout]).to include('hello')
      end
    end
  end
end
