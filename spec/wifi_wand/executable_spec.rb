# frozen_string_literal: true

require_relative '../spec_helper'
require 'open3'
require 'rbconfig'

def run_loaded_executable(path, *argv)
  repo_root = File.expand_path('../..', __dir__)
  ruby_source = <<~RUBY
    ARGV.replace(#{argv.inspect})
    load #{path.dump}
  RUBY

  stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', ruby_source, chdir: repo_root)
  {
    stdout:    stdout.force_encoding('UTF-8'),
    stderr:    stderr.force_encoding('UTF-8'),
    exit_code: status.exitstatus
  }
end

RSpec.describe 'exe/wifiwand' do
  let(:repo_root) { File.expand_path('../..', __dir__) }
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

  it 'no-command help hint refers to wifiwand, not wifi-wand' do
    result = run_loaded_executable(executable_path)

    # The program name in "Syntax is: <name>" reflects $0 at runtime, which is
    # "-e" under ruby -e. Assert on the help hint instead, which is hardcoded.
    expect(result[:stderr]).to include("'wifiwand help'")
    expect(result[:stderr]).not_to match(/wifi-wand/)
    expect(result[:stdout]).to eq('')
  end
end

RSpec.describe 'exe/wifi-wand (deprecated wrapper)' do
  let(:repo_root) { File.expand_path('../..', __dir__) }
  let(:executable_path) { File.join(repo_root, 'exe', 'wifi-wand') }

  it 'still works but prints a deprecation notice to stderr' do
    result = run_loaded_executable(executable_path, '--version')

    expect(result[:exit_code]).to eq(0)
    expect(result[:stdout]).to eq("#{WifiWand::VERSION}\n")
    expect(result[:stderr]).to match(/deprecated.*wifiwand/i)
  end
end
