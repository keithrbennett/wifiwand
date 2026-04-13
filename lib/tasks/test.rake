# frozen_string_literal: true

require 'rake'

namespace :test do
  def run_rspec(env = {}, *args)
    sh env, 'bundle', 'exec', 'rspec', *args
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

  desc 'Run specs with verbose WiFi command output (WIFIWAND_VERBOSE=true)'
  task :verbose do
    run_rspec({ 'WIFIWAND_VERBOSE' => 'true' })
  end

  desc 'Run specs with branch coverage enabled (COVERAGE_BRANCH=true)'
  task :branch do
    run_rspec({ 'COVERAGE_BRANCH' => 'true' })
  end
end

desc 'Run the default safe RSpec suite'
task test: 'test:safe'

desc 'Run the default safe RSpec suite'
task spec: 'test:safe'
