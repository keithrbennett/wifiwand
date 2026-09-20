# frozen_string_literal: true

require 'rake'

namespace :security do
  desc 'Audit dependencies for vulnerabilities with bundler-audit'
  task :bundler_audit do
    sh 'bundle exec bundle-audit check --update'
  end

  desc 'Audit Ruby and RubyGems for known vulnerabilities with ruby_audit'
  task :ruby_audit do
    sh 'bundle exec ruby-audit check'
  end

  desc 'Run all security audits'
  task :all do
    failures = []

    begin
      Rake::Task['security:bundler_audit'].invoke
    rescue => e
      failures << "bundler-audit failed: #{e.message}"
    end

    begin
      Rake::Task['security:ruby_audit'].invoke
    rescue => e
      failures << "ruby-audit failed: #{e.message}"
    end

    begin
      Rake::Task['docs:audit'].invoke
    rescue => e
      failures << "pip-audit failed: #{e.message}"
    end

    if failures.empty?
      puts '--- Security audits completed successfully ---'
      next
    end

    failures.each { |message| warn message }
    abort 'Security audits failed'
  end
end

desc 'Run all security audits'
task security: 'security:all'
