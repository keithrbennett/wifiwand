# frozen_string_literal: true

require_relative '../../spec_helper'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  include TestHelpers

  describe '#tcp_connectivity?' do

    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true, output: output) }

      before do
        mock_socket_connection_failure
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'outputs formatted endpoint list to stdout' do
        tester.tcp_connectivity?
        expect(output.string).to match(/Testing internet TCP connectivity to: .*:.*/)
      end

      it 'formats endpoints as host:port pairs separated by commas' do
        tester.tcp_connectivity?
        expect(output.string).to match(/1\.1\.1\.1:443.*8\.8\.8\.8:443.*208\.67\.222\.222:443/)
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        stub_short_connectivity_timeouts
        mock_socket_connection_failure
      end

      it 'returns false when all endpoints fail' do
        # Timeout wrapper ensures test doesn't hang if there's a bug
        result = Timeout.timeout(0.2) { tester.tcp_connectivity? }
        expect(result).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before { mock_socket_connection_success }

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end

    context 'when some ports are blocked but others remain open' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        allow(tester).to receive(:tcp_test_endpoints).and_return([
          { host: '1.1.1.1', port: 53 },
          { host: '1.1.1.1', port: 443 }
        ])

        allow(Socket).to receive(:tcp) do |host, port, connect_timeout:, &block|
          if port == 53
            raise Errno::ECONNREFUSED
          else
            block ? block.call : true
          end
        end
      end

      it 'still reports connectivity when an alternate port succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end
  end

  describe '#dns_working?' do

    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true, output: output) }

      before { mock_dns_resolution_failure }

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        stub_short_connectivity_timeouts
        mock_dns_resolution_failure
      end

      it 'returns false when all domains fail to resolve' do
        # Timeout wrapper ensures test doesn't hang if there's a bug
        result = Timeout.timeout(0.2) { tester.dns_working? }
        expect(result).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before { mock_dns_resolution_success }

      it 'returns true when at least one domain resolves' do
        expect(tester.dns_working?).to be true
      end
    end
  end

  describe '#connected_to_internet?' do
    let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

    it 'returns true when both TCP and DNS work' do
      allow(tester).to receive(:tcp_connectivity?).and_return(true)
      allow(tester).to receive(:dns_working?).and_return(true)

      expect(tester.connected_to_internet?).to be true
    end

    it 'returns false when TCP fails' do
      allow(tester).to receive(:tcp_connectivity?).and_return(false)
      allow(tester).to receive(:dns_working?).and_return(true)

      expect(tester.connected_to_internet?).to be false
    end

    it 'returns false when DNS fails' do
      allow(tester).to receive(:tcp_connectivity?).and_return(true)
      allow(tester).to receive(:dns_working?).and_return(false)

      expect(tester.connected_to_internet?).to be false
    end

    it 'returns false when both fail' do
      allow(tester).to receive(:tcp_connectivity?).and_return(false)
      allow(tester).to receive(:dns_working?).and_return(false)

      expect(tester.connected_to_internet?).to be false
    end
  end
end
