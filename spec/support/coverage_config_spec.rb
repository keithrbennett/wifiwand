# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverageConfig do
  around do |example|
    original_real_env_tests = ENV['WIFIWAND_REAL_ENV_TESTS']
    original_cobertura_coverage = ENV['WIFIWAND_COBERTURA_COVERAGE']

    example.run
  ensure
    ENV['WIFIWAND_REAL_ENV_TESTS'] = original_real_env_tests
    ENV['WIFIWAND_COBERTURA_COVERAGE'] = original_cobertura_coverage
  end

  describe '.setup' do
    it 'enables branch coverage by default' do
      enabled_coverage_types = []
      config_double = Object.new
      config_double.define_singleton_method(:track_files) { |_pattern| nil }
      config_double.define_singleton_method(:add_filter) { |_filter| nil }
      config_double.define_singleton_method(:add_group) { |_name, _filter| nil }
      config_double.define_singleton_method(:formatter) { |_formatter| nil }
      config_double.define_singleton_method(:enable_coverage) { |type| enabled_coverage_types << type }
      config_double.define_singleton_method(:source_in_json) { |_enabled| nil }

      allow(described_class).to receive(:configure_resultset_path!)
      allow(SimpleCov).to receive(:command_name)
      allow(SimpleCov).to receive(:start) { |&block| config_double.instance_eval(&block) }

      described_class.setup

      expect(enabled_coverage_types).to eq([:branch])
    end
  end

  describe '.tracked_runtime_globs' do
    it 'defines the broad packaged Ruby runtime surface' do
      expect(described_class.tracked_runtime_globs).to eq([
        'lib/**/*.rb',
        'exe/*',
      ])
    end
  end

  describe '.excluded_runtime_globs' do
    it 'defines maintainer-only files excluded from packaged runtime coverage' do
      expect(described_class.excluded_runtime_globs).to eq([
        'lib/wifi_wand/platforms/mac/helper/release.rb',
        'lib/wifi_wand/platforms/mac/helper/build.rb',
      ])
    end
  end

  describe '.excluded_runtime_files' do
    it 'expands maintainer-only files excluded from packaged runtime coverage' do
      expect(described_class.excluded_runtime_files).to include(
        'lib/wifi_wand/platforms/mac/helper/release.rb',
        'lib/wifi_wand/platforms/mac/helper/build.rb'
      )
    end
  end

  describe '.tracked_runtime_files' do
    it 'includes packaged runtime files' do
      expect(described_class.tracked_runtime_files).to include(
        'lib/wifi_wand.rb',
        'lib/wifi_wand/main.rb',
        'exe/wifi-wand',
        'exe/wifi-wand-macos-setup'
      )
    end

    it 'excludes maintainer-only files that are not packaged runtime' do
      expect(described_class.tracked_runtime_files).not_to include(
        'lib/wifi_wand/platforms/mac/helper/release.rb',
        'lib/wifi_wand/platforms/mac/helper/build.rb'
      )
    end
  end

  describe '.simplecov_tracked_patterns' do
    it 'tracks Ruby files exactly and extensionless executables by glob' do
      expect(described_class.simplecov_tracked_patterns).to include(
        'lib/wifi_wand.rb',
        'lib/wifi_wand/main.rb',
        'exe/*'
      )
      expect(described_class.simplecov_tracked_patterns).not_to include(
        'exe/wifi-wand',
        'exe/wifi-wand-macos-setup'
      )
    end
  end

  describe CoverageConfig::Formatters do
    subject(:formatters) { described_class }

    it 'returns true by default' do
      ENV.delete('WIFIWAND_COBERTURA_COVERAGE')

      expect(formatters.cobertura_coverage_enabled?).to be(true)
    end

    it 'returns the source flag value when the environment flag is unset' do
      ENV.delete('WIFIWAND_COBERTURA_COVERAGE')

      stub_const('CoverageConfig::Formatters::COBERTURA_COVERAGE_ENABLED', false)

      expect(formatters.cobertura_coverage_enabled?).to be(false)
    end

    it 'returns true for truthy flag values' do
      ENV['WIFIWAND_COBERTURA_COVERAGE'] = 'true'

      expect(formatters.cobertura_coverage_enabled?).to be(true)
    end

    it 'returns false for falsey flag values' do
      ENV['WIFIWAND_COBERTURA_COVERAGE'] = 'false'

      expect(formatters.cobertura_coverage_enabled?).to be(false)
    end

    it 'falls back to the source flag for unrecognized flag values' do
      ENV['WIFIWAND_COBERTURA_COVERAGE'] = 'maybe'

      expect(formatters.cobertura_coverage_enabled?).to be(true)
    end

    it 'excludes the Cobertura formatter when disabled' do
      ENV['WIFIWAND_COBERTURA_COVERAGE'] = 'false'

      expect(formatters.simplecov_formatters).to eq([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::SimpleFormatter,
      ])
    end

    it 'requires and includes the Cobertura formatter by default' do
      cobertura_formatter = Class.new
      ENV.delete('WIFIWAND_COBERTURA_COVERAGE')

      stub_const('SimpleCov::Formatter::CoberturaFormatter', cobertura_formatter)
      allow(formatters).to receive(:require).with('simplecov-cobertura')

      expect(formatters.simplecov_formatters).to eq([
        SimpleCov::Formatter::HTMLFormatter,
        cobertura_formatter,
        SimpleCov::Formatter::SimpleFormatter,
      ])
      expect(formatters).to have_received(:require).with('simplecov-cobertura')
    end
  end

  describe '.real_env_run?' do
    it 'returns false for ordinary runs' do
      ENV.delete('WIFIWAND_REAL_ENV_TESTS')

      expect(described_class.real_env_run?).to be(false)
    end

    it 'returns true for read-only real-environment runs' do
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'read_only'

      expect(described_class.real_env_run?).to be(true)
    end

    it 'returns true for all real-environment runs' do
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'all'

      expect(described_class.real_env_run?).to be(true)
    end
  end

  describe '.resultset_basename' do
    it 'uses the default resultset for ordinary runs' do
      ENV.delete('WIFIWAND_REAL_ENV_TESTS')

      expect(described_class.resultset_basename).to eq('.resultset.json')
    end

    it 'uses the OS-specific resultset for read-only real-environment runs' do
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'read_only'

      expect(described_class.resultset_basename).to match(/\.resultset\.(mac|ubuntu)\.json/)
    end

    it 'uses the OS-specific resultset for full real-environment runs' do
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'all'

      expect(described_class.resultset_basename).to match(/\.resultset\.(mac|ubuntu)\.json/)
    end
  end

  describe '.resultset_path' do
    it 'places the resultset under the coverage directory' do
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'read_only'

      expect(described_class.resultset_path).to match(%r{/coverage/\.resultset\.(mac|ubuntu)\.json\z})
    end
  end
end
