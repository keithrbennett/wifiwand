# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi_wand/runtime_config'

describe WifiWand::RuntimeConfig do
  describe '#to_h' do
    it 'returns the current verbose and output settings' do
      output = StringIO.new
      error_stringio = StringIO.new
      config = described_class.new(verbose: true, utc: true, out_stream: output, err_stream: error_stringio)

      expect(config.to_h).to eq(
        verbose:    true,
        utc:        true,
        out_stream: output,
        err_stream: error_stringio
      )
    end
  end

  describe 'boolean settings' do
    it 'coerces utc values to booleans' do
      config = described_class.new(utc: 'yes')
      expect(config.utc).to be true

      config.utc = nil
      expect(config.utc).to be false
    end
  end
end
