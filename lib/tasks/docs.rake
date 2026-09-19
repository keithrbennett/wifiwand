# frozen_string_literal: true

require 'rake'
require_relative '../wifi_wand/docs_tooling'

namespace :docs do
  desc 'Build documentation with mkdocs'
  task :build do
    Dir.chdir(Rake.application.original_dir) do
      sh RbConfig.ruby, WifiWand::DocsTooling.build_script_path, *WifiWand::DocsTooling.rake_passthrough_args
    end
  end

  desc 'Set up Python environment for the documentation server'
  task :setup do
    WifiWand::DocsTooling.setup_environment!
  end

  desc 'Audit locked documentation dependencies for known vulnerabilities (pip-audit)'
  task :audit do
    sh 'bash', File.join(WifiWand::DocsTooling::REPO_ROOT, 'bin', 'audit-docs-deps')
  end

  desc 'Regenerate requirements-lock.txt from requirements.txt'
  task :update_deps do
    sh 'bash', File.join(WifiWand::DocsTooling::REPO_ROOT, 'bin', 'update-docs-deps')
  end

  desc 'Start documentation server'
  task :serve do
    Dir.chdir(Rake.application.original_dir) do
      sh RbConfig.ruby, WifiWand::DocsTooling.start_server_script_path, *WifiWand::DocsTooling.rake_passthrough_args
    end
  end
end

desc 'Build documentation with mkdocs; `rake docs` defaults to build'
task docs: 'docs:build'
