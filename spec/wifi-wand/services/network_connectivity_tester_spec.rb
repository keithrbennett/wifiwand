# frozen_string_literal: true

require_relative '../../spec_helper'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  
  describe '#tcp_connectivity?' do

    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true, output: output) }

      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      end

      it 'outputs formatted endpoint list to stdout' do
        tester.tcp_connectivity?
        expect(output.string).to match(/Testing internet TCP connectivity to: .*:.*/)
      end

      it 'formats endpoints as host:port pairs separated by commas' do
        tester.tcp_connectivity?
        expect(output.string).to match(/1\.1\.1\.1:53.*8\.8\.8\.8:53.*208\.67\.222\.222:53/)
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        stub_const('WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT', 0.05)
        stub_const('WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT', 0.01)
        # Mock Socket.tcp to always raise connection refused
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns false when all endpoints fail' do
        # Timeout wrapper ensures test doesn't hang if there's a bug
        result = Timeout.timeout(0.2) { tester.tcp_connectivity? }
        expect(result).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        # Mock Socket.tcp to succeed (simulate successful connection)
        allow(Socket).to receive(:tcp).and_yield
      end

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end
  end

  describe '#dns_working?' do

    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true, output: output) }

      before do
        allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
      end

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        stub_const('WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT', 0.05)
        stub_const('WifiWand::TimingConstants::DNS_RESOLUTION_TIMEOUT', 0.01)
        # Mock IPSocket.getaddress to always raise socket error
        allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
      end

      it 'returns false when all domains fail to resolve' do
        # Timeout wrapper ensures test doesn't hang if there's a bug
        result = Timeout.timeout(0.2) { tester.dns_working? }
        expect(result).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        # Mock IPSocket.getaddress to succeed (simulate successful DNS resolution)
        allow(IPSocket).to receive(:getaddress).and_return('1.2.3.4')
      end

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
