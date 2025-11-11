# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WifiWand::MacOsWifiAuthHelper::Client do
  subject(:client) do
    described_class.new(
      out_stream_proc: -> { nil },
      verbose_proc: -> { false },
      macos_version_proc: -> { nil }
    )
  end

  describe '#sanitize_version_string' do
    it 'keeps only numeric segments from versions with build metadata in parentheses' do
      expect(client.send(:sanitize_version_string, '15.6 (24A335)')).to eq('15.6')
    end

    it 'removes prerelease suffixes like beta tags' do
      expect(client.send(:sanitize_version_string, '15.6.1-beta2')).to eq('15.6.1')
    end

    it 'returns nil when the version does not include numeric components' do
      expect(client.send(:sanitize_version_string, 'unknown')).to be_nil
    end
  end
end
