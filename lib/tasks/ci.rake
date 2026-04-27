# frozen_string_literal: true

require_relative '../wifi-wand/scripts/latest_ci_status'

namespace :ci do
  desc 'Get latest GitHub Actions status for the current branch'
  task :status do
    WifiWand::Scripts::LatestCiStatus.new.call
  end
end

desc 'Get latest GitHub Actions status for the current branch'
task ci: 'ci:status'
