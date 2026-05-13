# frozen_string_literal: true

RSpec.describe WifiWand::StringPredicates do
  describe '.string_nil_or_empty?' do
    {
      'returns true for nil'                     => { value: nil, expected: true },
      'returns true for an empty string'         => { value: '', expected: true },
      'returns false for a non-empty string'     => { value: 'wifi', expected: false },
      'returns false for whitespace'             => { value: ' ', expected: false },
      'returns false for an empty array'         => { value: [], expected: false },
      'returns false for an empty hash'          => { value: {}, expected: false },
      'returns false for an empty string symbol' => { value: :'', expected: false },
    }.each do |description, data|
      it description do
        expect(described_class.string_nil_or_empty?(data[:value])).to eq(data[:expected])
      end
    end
  end

  describe '.string_nil_or_blank?' do
    {
      'returns true for nil'                     => { value: nil, expected: true },
      'returns true for an empty string'         => { value: '', expected: true },
      'returns true for whitespace'              => { value: ' ', expected: true },
      'returns false for a non-empty string'     => { value: 'wifi', expected: false },
      'returns false for an empty array'         => { value: [], expected: false },
      'returns false for an empty hash'          => { value: {}, expected: false },
      'returns false for an empty string symbol' => { value: :'', expected: false },
    }.each do |description, data|
      it description do
        expect(described_class.string_nil_or_blank?(data[:value])).to eq(data[:expected])
      end
    end
  end
end
