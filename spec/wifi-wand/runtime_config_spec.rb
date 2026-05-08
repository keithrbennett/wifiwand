# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi_wand/runtime_config'

describe WifiWand::RuntimeConfig do
  describe '#to_h' do
    it 'returns the current verbose and output settings' do
      output = StringIO.new
      error_stringio = StringIO.new
      config = described_class.new(verbose: true, out_stream: output, err_stream: error_stringio)

      expect(config.to_h).to eq(
        verbose:    true,
        out_stream: output,
        err_stream: error_stringio
      )
    end
  end
end
