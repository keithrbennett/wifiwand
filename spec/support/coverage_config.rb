# frozen_string_literal: true

require 'simplecov'

module CoverageConfig
  DEFAULT_RESULTSET_BASENAME = '.resultset.json'
  NATIVE_FULL_RESULTSET_TEMPLATE = '.resultset.json.%<os>s.all'
  VALID_COVERAGE_MODES = %w[default native_all].freeze

  def self.setup
    validate_coverage_mode!

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
    SimpleCov.command_name("rspec-#{coverage_mode}")
  end

  def self.coverage_mode
    mode = ENV.fetch('WIFIWAND_COVERAGE_MODE', 'default')
    return mode if VALID_COVERAGE_MODES.include?(mode)

    raise ArgumentError,
      "Invalid WIFIWAND_COVERAGE_MODE=#{mode.inspect}. Valid options: #{VALID_COVERAGE_MODES.join(', ')}"
  end

  def self.resultset_basename
    return DEFAULT_RESULTSET_BASENAME unless coverage_mode == 'native_all'

    format(NATIVE_FULL_RESULTSET_TEMPLATE, os: native_os_name)
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
      raise ArgumentError, 'WIFIWAND_COVERAGE_MODE=native_all requires a native macOS or Ubuntu host'
    end
  end

  def self.native_all_run?
    ENV.fetch('WIFIWAND_REAL_ENV_TESTS', 'none') == 'all'
  end

  def self.validate_coverage_mode!
    return unless coverage_mode == 'native_all'
    return if native_all_run?

    raise ArgumentError,
      'WIFIWAND_COVERAGE_MODE=native_all requires WIFIWAND_REAL_ENV_TESTS=all'
  end

  def self.configure_resultset_path!
    path = resultset_path
    lock_path = resultset_lock_path
    result_merger = SimpleCov::ResultMerger.singleton_class

    result_merger.send(:define_method, :resultset_path) { path }
    result_merger.send(:define_method, :resultset_writelock) { lock_path }
  end
end
