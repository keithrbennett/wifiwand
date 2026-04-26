# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/runtime_config'

describe WifiWand::RuntimeConfig do
  describe '#to_h' do
    it 'returns the current verbose and output settings' do
      output = StringIO.new
      config = described_class.new(verbose: true, out_stream: output)

      expect(config.to_h).to eq(
        verbose:    true,
        out_stream: output
      )
    end
  end
end
