# frozen_string_literal: true

namespace :docs do
  desc 'Build documentation with mkdocs'
  task :build do
    sh 'bin/build-docs'
  end

  desc 'Set up Python environment for the documentation server'
  task :setup do
    sh 'bash', '-lc', 'python3 -m venv .docs-venv && .docs-venv/bin/pip install -q -r requirements-lock.txt'
  end

  desc 'Start documentation server'
  task :serve do
    sh 'bin/start-doc-server'
  end
end

desc 'Build documentation with mkdocs; `rake docs` defaults to build'
task docs: 'docs:build'
