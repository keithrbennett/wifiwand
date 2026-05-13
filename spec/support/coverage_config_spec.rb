# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverageConfig do
  around do |example|
    original_real_env_tests = ENV['WIFIWAND_REAL_ENV_TESTS']

    example.run
  ensure
    ENV['WIFIWAND_REAL_ENV_TESTS'] = original_real_env_tests
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
        'lib/wifi_wand/mac_helper/mac_helper_release.rb',
        'lib/wifi_wand/mac_helper/mac_os_helper_build.rb',
      ])
    end
  end

  describe '.excluded_runtime_files' do
    it 'expands maintainer-only files excluded from packaged runtime coverage' do
      expect(described_class.excluded_runtime_files).to include(
        'lib/wifi_wand/mac_helper/mac_helper_release.rb',
        'lib/wifi_wand/mac_helper/mac_os_helper_build.rb'
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
        'lib/wifi_wand/mac_helper/mac_helper_release.rb',
        'lib/wifi_wand/mac_helper/mac_os_helper_build.rb'
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
