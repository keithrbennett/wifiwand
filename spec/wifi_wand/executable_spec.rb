# frozen_string_literal: true

require_relative '../spec_helper'
require 'open3'
require 'rbconfig'

def run_loaded_executable(path, *argv)
  repo_root = File.expand_path('../..', __dir__)
  # Set $0 to the executable path so File.basename($PROGRAM_NAME) in the CLI
  # produces the correct executable name, matching what RubyGems wrappers do.
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

RSpec.describe 'exe/' do
  let(:repo_root) { File.expand_path('../..', __dir__) }

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

      expect(result[:stderr]).to include('Syntax is: wifiwand')
      expect(result[:stderr]).to include("'wifiwand help'")
      expect(result[:stderr]).not_to include('wifi-wand')
      expect(result[:stdout]).to eq('')
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
  end
end
