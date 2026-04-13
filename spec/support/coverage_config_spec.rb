# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverageConfig do
  around do |example|
    original_real_env_tests = ENV['WIFIWAND_REAL_ENV_TESTS']

    example.run
  ensure
    ENV['WIFIWAND_REAL_ENV_TESTS'] = original_real_env_tests
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
