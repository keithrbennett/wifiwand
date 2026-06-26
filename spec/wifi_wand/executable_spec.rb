# frozen_string_literal: true

require_relative '../spec_helper'
require 'open3'
require 'rbconfig'
require 'timeout'

RSpec.describe 'exe/' do
  let(:repo_root) { File.expand_path('../..', __dir__) }

  # Runs the executable via a RubyGems-style load wrapper.
  # Sets $0 to the executable path so File.basename($PROGRAM_NAME) in the CLI
  # resolves to the correct executable name, matching what RubyGems wrappers do.
  def run_loaded_executable(path, *argv)
    repo_root = File.expand_path('../..', __dir__)
    ruby_source = <<~RUBY
      $0 = #{path.dump}
      ARGV.replace(#{argv.inspect})
      load #{path.dump}
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', ruby_source, chdir: repo_root)
    {
      stdout:    stdout.force_encoding('UTF-8'),
      stderr:    stderr.force_encoding('UTF-8'),
      exit_code: status.exitstatus,
    }
  end

  # Wait up to timeout_seconds for the subprocess thread to be alive.
  # Raises Timeout::Error if it never starts, so premature death fails loudly.
  def wait_for_process(wait_thr, timeout_seconds = 5)
    Timeout.timeout(timeout_seconds) do
      sleep 0.01 until wait_thr.alive?
    end
  end

  describe 'wifiwand' do
    let(:executable_path) { File.join(repo_root, 'exe', 'wifiwand') }

    it 'runs when loaded through a RubyGems-style wrapper' do
      result = run_loaded_executable(executable_path, '--version')

      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to eq("#{WifiWand::VERSION}\n")
      expect(result[:stderr]).to eq('')
    end

    it 'usage output refers to wifiwand, not wifi-wand' do
      result = run_loaded_executable(executable_path, '--help')

      expect(result[:stdout]).to include('wifiwand')
      expect(result[:stdout]).not_to match(/Usage:.*wifi-wand/)
      expect(result[:stderr]).to eq('')
    end

    it 'no-command syntax output names the wifiwand executable' do
      result = run_loaded_executable(executable_path)

      expect(result[:exit_code]).to eq(1)
      expect(result[:stderr]).to include('Syntax is: wifiwand')
      expect(result[:stderr]).to include("'wifiwand help'")
      expect(result[:stderr]).not_to include('wifi-wand')
      expect(result[:stdout]).to eq('')
    end

    it 'exits 143 and prints a friendly message when sent SIGTERM' do
      stderr_str = ''
      status = nil

      ruby_source = <<~RUBY
        ARGV.replace(['shell'])
        load #{executable_path.dump}
      RUBY

      Open3.popen3(RbConfig.ruby, '-e', ruby_source, chdir: repo_root) do |_stdin, stdout, stderr, wait_thr|
        pid = wait_thr.pid
        wait_for_process(wait_thr, external_process_timeout)

        # Wait for Pry to emit a prompt so we know the shell (and SIGTERM trap)
        # are fully up before we signal the process.
        buffer = +''
        Timeout.timeout(external_process_timeout) do
          loop do
            buffer << stdout.readpartial(1024)
            break if buffer.match?(/\[\d+\] pry/)
          end
        end

        Process.kill('TERM', pid)
        Timeout.timeout(external_process_timeout) do
          stdout.read
          stderr_str = stderr.read
          status = wait_thr.value
        end
      end

      aggregate_failures do
        expect(status.exitstatus).to eq(143)
        expect(stderr_str).to include('Error: Terminated by SIGTERM.')
      end
    end

    it 'skips the Ruby version guard when --disable-gems is active' do
      ruby_source = <<~RUBY
        module Kernel
          alias_method :orig_require, :require
          def require(name)
            if name == 'rubygems'
              warn "TEST ABORT: require 'rubygems' was called despite --disable-gems"
              exit 99
            end
            orig_require(name)
          end
        end
        $0 = #{executable_path.dump}
        ARGV.replace(['--version'])
        load #{executable_path.dump}
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, '--disable-gems', '-e', ruby_source, chdir: repo_root
      )

      aggregate_failures do
        expect(status.exitstatus).to eq(0)
        expect(stderr).not_to include('TEST ABORT')
        expect(stderr).not_to include('uninitialized constant WifiWandExecutable::Gem')
        expect(stdout).to eq("#{WifiWand::VERSION}\n")
      end
    end

    it 'fails fast with a friendly message when Ruby is below the minimum' do
      ruby_source = <<~RUBY
        $0 = #{executable_path.dump}
        Object.send(:remove_const, :RUBY_VERSION)
        RUBY_VERSION = '2.6.0'
        load #{executable_path.dump}
      RUBY

      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', ruby_source, chdir: repo_root)

      aggregate_failures do
        expect(status.exitstatus).to eq(1)
        expect(stderr).to include('wifiwand requires Ruby >= 3.2')
        expect(stderr).to include('Please run with a supported Ruby version')
      end
    end
  end

  describe 'wifi-wand (deprecated wrapper)' do
    let(:executable_path) { File.join(repo_root, 'exe', 'wifi-wand') }

    it 'still works but prints a deprecation notice to stderr' do
      result = run_loaded_executable(executable_path, '--version')

      expect(result[:exit_code]).to eq(0)
      expect(result[:stdout]).to eq("#{WifiWand::VERSION}\n")
      expect(result[:stderr]).to match(/deprecated.*wifiwand/i)
    end

    it 'no-command syntax output names wifiwand, not wifi-wand' do
      result = run_loaded_executable(executable_path)

      expect(result[:exit_code]).to eq(1)
      expect(result[:stderr]).to include('Syntax is: wifiwand')
      expect(result[:stderr]).to include("'wifiwand help'")
      expect(result[:stderr]).not_to match(/Syntax is:.*wifi-wand/)
      expect(result[:stdout]).to eq('')
    end
  end

  describe 'wifi-wand-macos-setup (deprecated wrapper)' do
    let(:executable_path) { File.join(repo_root, 'exe', 'wifi-wand-macos-setup') }

    it 'prints a deprecation notice to stderr and delegates' do
      result = run_loaded_executable(executable_path, '--version')

      expect(result[:stderr]).to match(/deprecated.*wifiwand-macos-setup/i)
    end
  end
end
