# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/helpers/security_type_normalizer'

describe WifiWand::Models::Helpers::SecurityTypeNormalizer do
  describe '.canonical_security_type_from' do
    it 'returns nil for nil input' do
      expect(described_class.canonical_security_type_from(nil)).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.canonical_security_type_from('')).to be_nil
    end

    it 'returns nil for whitespace-only input' do
      expect(described_class.canonical_security_type_from('   ')).to be_nil
    end

    describe 'canonical mapping' do
      {
        'wpa3'                         => 'WPA3',
        'WPA3 Personal'                => 'WPA3',
        'WPA3 Enterprise'              => nil,
        'wpa2'                         => 'WPA2',
        'WPA2 Personal'                => 'WPA2',
        'WPA2 Enterprise'              => nil,
        'WPA2-Enterprise'              => nil,
        '802.1x'                       => nil,
        '8021x'                        => nil,
        'WPA1'                         => 'WPA',
        'WPA'                          => 'WPA',
        'WPA Personal'                 => 'WPA',
        'WPA-Personal'                 => 'WPA',
        'WEP'                          => 'WEP',
        'WEP Transitional'             => 'WEP',
        'none'                         => 'NONE',
        'NONE'                         => 'NONE',
        'spairport_security_mode_none' => 'NONE',
        'SPAIRPORT_SECURITY_MODE_NONE' => 'NONE',
        'owe'                          => 'NONE',
        'OWE'                          => 'NONE',
        'RSN'                          => nil,
        'bogus'                        => nil,
      }.each do |input, expected|
        it "normalizes #{input.inspect} to #{expected.inspect}" do
          expect(described_class.canonical_security_type_from(input)).to eq(expected)
        end
      end
    end
  end
end
