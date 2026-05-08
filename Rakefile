# frozen_string_literal: true

repo_root = File.expand_path(__dir__)

Dir.chdir(repo_root)

require 'bundler/gem_tasks'
require 'rbconfig'
require_relative 'lib/wifi_wand/mac_helper/mac_os_helper_bundle'

Dir.glob(File.expand_path('lib/tasks/**/*.rake', repo_root)).each do |task_file|
  import task_file
end
