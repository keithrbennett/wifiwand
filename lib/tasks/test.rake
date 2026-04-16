# frozen_string_literal: true

require 'rake'
require 'shellwords'

namespace :test do
  def run_rspec(env = {}, *args)
    sh env, 'bundle', 'exec', 'rspec', *args
  end

  def rspec_args_from(targets)
    return [] if targets.nil? || targets.strip.empty?

    Shellwords.split(targets)
  end

  desc 'Run the default safe RSpec suite'
  task :safe do
    run_rspec
  end

  desc 'Run read-only real-environment specs too (WIFIWAND_REAL_ENV_TESTS=read_only)'
  task :read_only do
    run_rspec({ 'WIFIWAND_REAL_ENV_TESTS' => 'read_only' })
  end

  desc 'Run all real-environment specs, including read-write coverage (WIFIWAND_REAL_ENV_TESTS=all)'
  task :all do
    run_rspec({ 'WIFIWAND_REAL_ENV_TESTS' => 'all' })
  end

  desc 'Run targeted read-only real-environment specs'
  task :read_only_target, [:targets] do |_task, args|
    run_rspec({ 'WIFIWAND_REAL_ENV_TESTS' => 'read_only' }, *rspec_args_from(args[:targets]))
  end

  desc 'Run targeted real-environment specs'
  task :real, [:targets] do |_task, args|
    run_rspec({ 'WIFIWAND_REAL_ENV_TESTS' => 'all' }, *rspec_args_from(args[:targets]))
  end
end

desc 'Run the default safe RSpec suite'
task test: 'test:safe'

desc 'Run the default safe RSpec suite'
task spec: 'test:safe'
