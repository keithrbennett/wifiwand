# frozen_string_literal: true

require 'simplecov'

module CoverageConfig
  DEFAULT_RESULTSET_BASENAME = '.resultset.json'
  REAL_ENV_RESULTSET_TEMPLATE = '.resultset.%<os>s.json'

  def self.setup
    SimpleCov.start do
      add_filter '/spec/'
      add_filter '/vendor/'
      add_filter '/tmp/'

      # Group coverage by directory
      add_group 'Models', 'lib/wifi-wand/models'
      add_group 'Services', 'lib/wifi-wand/services'
      add_group 'OS Detection', 'lib/wifi-wand/os'
      add_group 'Core', 'lib/wifi-wand'

      # Generate multiple output formats
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::SimpleFormatter,
      ])

      # Only track coverage when running the full test suite
      enable_coverage :branch if ENV['COVERAGE_BRANCH'] == 'true'
    end

    configure_resultset_path!
    SimpleCov.command_name("rspec-#{coverage_label}")
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
end
