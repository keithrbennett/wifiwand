# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EnvBoolean do
  describe '.enabled?' do
    it 'returns the default when the key is unset' do
      expect(described_class.enabled?({}, 'FEATURE_FLAG', default: true)).to be(true)
      expect(described_class.enabled?({}, 'FEATURE_FLAG', default: false)).to be(false)
    end

    it 'returns true for recognized truthy values' do
      described_class::TRUE_VALUES.each do |value|
        expect(
          described_class.enabled?({ 'FEATURE_FLAG' => value }, 'FEATURE_FLAG', default: false)
        ).to be(true)
      end
    end

    it 'returns false for recognized falsey values' do
      described_class::FALSE_VALUES.each do |value|
        expect(
          described_class.enabled?({ 'FEATURE_FLAG' => value }, 'FEATURE_FLAG', default: true)
        ).to be(false)
      end
    end

    it 'ignores case and surrounding whitespace' do
      expect(
        described_class.enabled?({ 'FEATURE_FLAG' => ' TRUE ' }, 'FEATURE_FLAG', default: false)
      ).to be(true)
      expect(
        described_class.enabled?({ 'FEATURE_FLAG' => ' OFF ' }, 'FEATURE_FLAG', default: true)
      ).to be(false)
    end

    it 'returns the default for unrecognized values' do
      expect(
        described_class.enabled?({ 'FEATURE_FLAG' => 'maybe' }, 'FEATURE_FLAG', default: true)
      ).to be(true)
      expect(
        described_class.enabled?({ 'FEATURE_FLAG' => 'maybe' }, 'FEATURE_FLAG', default: false)
      ).to be(false)
    end
  end
end
