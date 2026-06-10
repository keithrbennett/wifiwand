# frozen_string_literal: true

require_relative '../spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'exe/wifi-wand' do
  let(:repo_root) { File.expand_path('../..', __dir__) }
  let(:executable_path) { File.join(repo_root, 'exe', 'wifi-wand') }

  def run_loaded_executable(*argv)
    ruby_source = <<~RUBY
      ARGV.replace(#{argv.inspect})
      load #{executable_path.dump}
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', ruby_source, chdir: repo_root)
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
  end

  it 'runs when loaded through a RubyGems-style wrapper' do
    result = run_loaded_executable('--version')

    expect(result[:exit_code]).to eq(0)
    expect(result[:stdout]).to eq("#{WifiWand::VERSION}\n")
    expect(result[:stderr]).to eq('')
  end
end
