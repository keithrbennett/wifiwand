# frozen_string_literal: true

require_relative '../spec_helper'
require 'tempfile'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'

# Load the helper methods from bin/op-wrap without triggering main execution.
# The __FILE__ == $PROGRAM_NAME guard in the script ensures only the method
# definitions are evaluated when the file is loaded via `load`.
load File.expand_path('../../bin/op-wrap', __dir__)

OP_WRAP_PATH = File.expand_path('../../bin/op-wrap', __dir__)

RSpec.describe 'bin/op-wrap' do
  # Helper: temporarily override ENV variables for the duration of a block.
  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [k, ENV[k]] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end

  # Helper: create a real executable file in a temp directory and yield its path.
  def with_fake_op_in_tmpdir(name: 'op')
    dir = Dir.mktmpdir
    path = File.join(dir, name)
    FileUtils.touch(path)
    File.chmod(0o755, path)
    yield dir, path
  ensure
    FileUtils.rm_rf(dir)
  end

  # Helper: run the script in a subprocess and return stdout, stderr, and exit_code.
  # Passes env as a hash to Open3 so that overriding PATH does not prevent Ruby itself
  # from being found (Open3 looks up the interpreter before applying the child env).
  def run_op_wrap(env: {}, argv: [])
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, OP_WRAP_PATH, *argv)
    { stdout:, stderr:, exit_code: status.exitstatus }
  end

  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
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
      captured = StringIO.new
      $stderr = captured
      begin
        check_op_available!('/nonexistent/op')
      rescue SystemExit
        # expected — we only care about the stderr content
      ensure
        $stderr = STDERR
      end
      expect(captured.string).to match(/not found in PATH/)
    end
  end

  # ---------------------------------------------------------------------------
  describe '#show_usage_and_exit' do
    it 'exits with code 64' do
      expect { show_usage_and_exit }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(64)
      end
    end

    it 'prints usage information to stderr' do
      captured = StringIO.new
      $stderr = captured
      begin
        show_usage_and_exit
      rescue SystemExit
        # expected
      ensure
        $stderr = STDERR
      end
      expect(captured.string).to match(/Usage:/)
    end
  end

  # ---------------------------------------------------------------------------
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
  end
end
