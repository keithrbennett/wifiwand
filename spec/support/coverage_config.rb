# frozen_string_literal: true

require 'simplecov'
require 'simplecov-cobertura'

module CoverageConfig
  PROJECT_ROOT = File.expand_path('../..', __dir__)
  DEFAULT_RESULTSET_BASENAME = '.resultset.json'
  REAL_ENV_RESULTSET_TEMPLATE = '.resultset.%<os>s.json'
  TRACKED_RUNTIME_GLOBS = [
    'lib/**/*.rb',
    'exe/*',
  ].freeze
  EXCLUDED_RUNTIME_GLOBS = [
    'lib/wifi_wand/platforms/mac/helper/release.rb',
    'lib/wifi_wand/platforms/mac/helper/build.rb',
  ].freeze

  def self.setup
    configure_resultset_path!
    SimpleCov.command_name("rspec-#{coverage_label}")

    SimpleCov.start do
      CoverageConfig.simplecov_tracked_patterns.each { |pattern| track_files pattern }
      CoverageConfig.excluded_runtime_files.each { |file| add_filter file }

      add_filter '/spec/'
      add_filter '/vendor/'
      add_filter '/tmp/'

      # Group coverage by directory
      add_group 'Shared Models', 'lib/wifi_wand/models'
      add_group 'Platforms', 'lib/wifi_wand/platforms'
      add_group 'Services', 'lib/wifi_wand/services'
      add_group 'Core', 'lib/wifi_wand'

      # Generate multiple output formats
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::CoberturaFormatter,
        SimpleCov::Formatter::SimpleFormatter,
      ])

      # Only track coverage when running the full test suite
      enable_coverage :branch if ENV['COVERAGE_BRANCH'] == 'true'

      # Newer versions of SimpleCov by default include all the source code covered in coverage.json.
      # This call will exclude that source code.
      # Older versions of simplecov do not have or need this call since they do not include the source code.
      source_in_json(false) if respond_to?(:source_in_json)
    end
  end

  def self.tracked_runtime_globs = TRACKED_RUNTIME_GLOBS

  def self.excluded_runtime_globs = EXCLUDED_RUNTIME_GLOBS

  def self.excluded_runtime_files = relative_files_matching(excluded_runtime_globs)

  def self.simplecov_tracked_patterns
    tracked_runtime_files.reject { |file| file.start_with?('exe/') } + ['exe/*']
  end

  def self.tracked_runtime_files
    included_files = relative_files_matching(tracked_runtime_globs)
    excluded_files = excluded_runtime_files

    included_files.reject { |file| excluded_files.include?(file) }
  end

  def self.coverage_label = real_env_run? ? 'real_env' : 'default'

  def self.resultset_basename
    real_env_run? ? format(REAL_ENV_RESULTSET_TEMPLATE, os: native_os_name) : DEFAULT_RESULTSET_BASENAME
  end

  def self.resultset_path
    File.join(SimpleCov.coverage_path, resultset_basename)
  end

  def self.resultset_lock_path
    "#{resultset_path}.lock"
  end

  def self.native_os_name
    case RbConfig::CONFIG.fetch('host_os')
    when /darwin/i
      'mac'
    when /linux/i
      'ubuntu'
    else
      raise ArgumentError, 'Real-environment coverage requires a native macOS or Ubuntu host'
    end
  end

  def self.real_env_run?
    ENV.fetch('WIFIWAND_REAL_ENV_TESTS', 'none') != 'none'
  end

  def self.configure_resultset_path!
    path = resultset_path
    lock_path = resultset_lock_path
    result_merger = SimpleCov::ResultMerger.singleton_class

    result_merger.send(:define_method, :resultset_path) { path }
    result_merger.send(:define_method, :resultset_writelock) { lock_path }
  end

  def self.relative_files_matching(globs)
    matched_files = globs.flat_map do |glob|
      Dir.glob(File.join(PROJECT_ROOT, glob)).select { |path| File.file?(path) }
    end

    matched_files.sort.map { |path| path.delete_prefix("#{PROJECT_ROOT}/") }
  end
end
