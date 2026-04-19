# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_probe_helper'

describe WifiWand::NetworkConnectivityProbeHelper do
  describe '.parse_argv' do
    it 'parses tcp arguments into a host and integer port' do
      result = described_class.parse_argv(%w[tcp example.com 443])

      expect(result).to eq(mode: :tcp, target: { host: 'example.com', port: 443 })
    end

    it 'parses dns arguments into a domain target' do
      result = described_class.parse_argv(%w[dns example.com])

      expect(result).to eq(mode: :dns, target: 'example.com')
    end

    it 'raises ArgumentError for an unsupported mode' do
      expect { described_class.parse_argv(%w[icmp example.com]) }
        .to raise_error(ArgumentError, /mode must be tcp, fast_tcp, or dns/)
    end
  end

  describe '.run' do
    let(:output) { StringIO.new }
    let(:tester) { instance_double(WifiWand::NetworkConnectivityTester) }

    it 'invokes the tester through the explicit public probe interface' do
      expect(tester).to receive(:run_probe)
        .with(:tcp, { host: 'example.com', port: 443 })
        .and_return(true)

      described_class.run(%w[tcp example.com 443], output: output, tester: tester)

      expect(JSON.parse(output.string, symbolize_names: true)).to eq(success: true)
    end

    it 'serializes helper errors as a failed probe result' do
      allow(tester).to receive(:run_probe).and_raise(ArgumentError, 'bad probe')

      described_class.run(%w[dns example.com], output: output, tester: tester)

      expect(JSON.parse(output.string, symbolize_names: true)).to eq(
        success:       false,
        error_class:   'ArgumentError',
        error_message: 'bad probe'
      )
    end
  end

  describe '.run_probe' do
    let(:tester) { instance_double(WifiWand::NetworkConnectivityTester) }

    it 'delegates probe execution to the tester public interface' do
      probe = { mode: :fast_tcp, target: { host: '1.1.1.1', port: 443 } }
      expect(tester).to receive(:run_probe).with(:fast_tcp, probe[:target]).and_return(false)

      expect(described_class.run_probe(tester, probe)).to be false
    end
  end
end
