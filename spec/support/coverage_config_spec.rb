# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverageConfig do
  around do |example|
    original_mode = ENV['WIFIWAND_COVERAGE_MODE']
    original_real_env_tests = ENV['WIFIWAND_REAL_ENV_TESTS']

    example.run
  ensure
    ENV['WIFIWAND_COVERAGE_MODE'] = original_mode
    ENV['WIFIWAND_REAL_ENV_TESTS'] = original_real_env_tests
  end

  describe '.coverage_mode' do
    it 'defaults to default mode' do
      ENV.delete('WIFIWAND_COVERAGE_MODE')

      expect(described_class.coverage_mode).to eq('default')
    end

    it 'rejects unsupported modes' do
      ENV['WIFIWAND_COVERAGE_MODE'] = 'mystery'

      expect { described_class.coverage_mode }
        .to raise_error(ArgumentError, /Invalid WIFIWAND_COVERAGE_MODE/)
    end
  end

  describe '.resultset_basename' do
    it 'uses the default resultset for ordinary runs' do
      ENV['WIFIWAND_COVERAGE_MODE'] = 'default'

      expect(described_class.resultset_basename).to eq('.resultset.json')
    end

    it 'uses the native full-suite artifact name when requested' do
      ENV['WIFIWAND_COVERAGE_MODE'] = 'native_all'

      expect(described_class.resultset_basename).to match(/\.resultset\.json\.(mac|ubuntu)\.all/)
    end
  end

  describe '.validate_coverage_mode!' do
    it 'allows default mode without extra env vars' do
      ENV['WIFIWAND_COVERAGE_MODE'] = 'default'
      ENV.delete('WIFIWAND_REAL_ENV_TESTS')

      expect { described_class.validate_coverage_mode! }.not_to raise_error
    end

    it 'rejects native_all when the full native suite is not selected' do
      ENV['WIFIWAND_COVERAGE_MODE'] = 'native_all'
      ENV['WIFIWAND_REAL_ENV_TESTS'] = 'read_only'

      expect { described_class.validate_coverage_mode! }
        .to raise_error(ArgumentError, /WIFIWAND_REAL_ENV_TESTS=all/)
    end
  end
end
