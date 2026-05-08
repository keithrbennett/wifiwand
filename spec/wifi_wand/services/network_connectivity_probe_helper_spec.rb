# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'stringio'
require_relative '../../../lib/wifi_wand/services/network_connectivity_probe_helper'

describe WifiWand::NetworkConnectivityProbeHelper do
  describe '.parse_argv' do
    it 'parses tcp probe batches from JSON' do
      result = described_class.parse_argv([
        'tcp',
        JSON.generate([{ host: 'example.com', port: 443 }]),
        '0.5',
      ])

      expect(result).to eq(
        mode:    :tcp,
        items:   [{ host: 'example.com', port: 443 }],
        timeout: 0.5
      )
    end

    it 'parses dns probe batches from JSON' do
      result = described_class.parse_argv(['dns', JSON.generate(['example.com']), '0.5'])

      expect(result).to eq(mode: :dns, items: ['example.com'], timeout: 0.5)
    end

    it 'raises ArgumentError for an unsupported mode' do
      expect { described_class.parse_argv(['icmp', '[]', '0.5']) }
        .to raise_error(ArgumentError, /mode must be tcp or dns/)
    end

    it 'raises ArgumentError when probe items are not a JSON array' do
      expect { described_class.parse_argv(['tcp', JSON.generate(host: 'example.com', port: 443), '0.5']) }
        .to raise_error(ArgumentError, /probe items must be an array/)
    end
  end

  describe '.run' do
    let(:output) { StringIO.new }
    let(:tester) { instance_double(WifiWand::NetworkConnectivityTester) }

    it 'serializes success when any probe succeeds' do
      items = [
        { host: 'failed.test', port: 443 },
        { host: 'success.test', port: 443 },
      ]
      allow(tester).to receive(:run_probe_result) do |_mode, item|
        { success: item[:host] == 'success.test', error_class: 'SocketError' }
      end

      described_class.run(
        ['tcp', JSON.generate(items), '1'],
        output: output,
        tester: tester
      )

      payload = JSON.parse(output.string, symbolize_names: true)
      expect(payload).to include(success: true, timed_out: false)
      expect(payload[:probe_results]).to include(
        { target: { host: 'success.test', port: 443 }, success: true, error_class: 'SocketError' }
      )
    end

    it 'serializes timeout when probes do not finish within the budget' do
      blocked_probe_release = Queue.new
      allow(tester).to receive(:run_probe_result) { blocked_probe_release.pop }

      described_class.run(
        ['dns', JSON.generate(%w[hung-a.test hung-b.test]), '0.05'],
        output: output,
        tester: tester
      )

      expect(JSON.parse(output.string, symbolize_names: true)).to eq(
        success:       false,
        timed_out:     true,
        probe_results: []
      )
    end

    it 'serializes helper errors as a failed probe result' do
      described_class.run(['dns', '{bad-json', '1'], output: output, tester: tester)

      expect(JSON.parse(output.string, symbolize_names: true)).to include(
        success:     false,
        timed_out:   false,
        error_class: 'JSON::ParserError'
      )
    end
  end

  describe '.parallel_probe_result' do
    let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

    it 'uses Socket.tcp with the configured connect timeout for TCP probes' do
      connect_timeouts = []
      allow(Socket).to receive(:tcp) do |_host, _port, connect_timeout:, &block|
        connect_timeouts << connect_timeout
        block.call
      end

      result = described_class.parallel_probe_result(
        tester,
        :tcp,
        [{ host: 'success.test', port: 443 }],
        1
      )

      expect(result).to eq(
        success:       true,
        timed_out:     false,
        probe_results: [
          { target: { host: 'success.test', port: 443 }, success: true, error_class: nil },
        ]
      )
      expect(connect_timeouts).to all(eq(WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT))
    end

    it 'uses IPSocket.getaddress for DNS probes' do
      allow(IPSocket).to receive(:getaddress).with('success.test').and_return('1.2.3.4')

      result = described_class.parallel_probe_result(tester, :dns, ['success.test'], 1)

      expect(result).to eq(
        success:       true,
        timed_out:     false,
        probe_results: [{ target: 'success.test', success: true, error_class: nil }]
      )
      expect(IPSocket).to have_received(:getaddress).with('success.test')
    end
  end
end
