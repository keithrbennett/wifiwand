# frozen_string_literal: true

require_relative '../wifi-wand/docs_tooling'

namespace :docs do
  desc 'Build documentation with mkdocs'
  task :build do
    sh WifiWand::DocsTooling.build_script_path
  end

  desc 'Set up Python environment for the documentation server'
  task :setup do
    WifiWand::DocsTooling.setup_environment!
  end

  desc 'Start documentation server'
  task :serve do
    sh WifiWand::DocsTooling.start_server_script_path
  end
end

desc 'Build documentation with mkdocs; `rake docs` defaults to build'
task docs: 'docs:build'
