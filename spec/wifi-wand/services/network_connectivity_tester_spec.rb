require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  
  describe '#tcp_connectivity?' do

    context 'with verbose mode enabled' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true) }

      before do
        # Mock Socket to prevent actual network calls
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      end

      it 'outputs formatted endpoint list to stdout' do
        # Capture stdout to verify the formatted output
        expect { tester.tcp_connectivity? }.to output(
          a_string_matching(/Testing internet TCP connectivity to: .*:.*/)
        ).to_stdout
      end

      it 'formats endpoints as host:port pairs separated by commas' do
        expect { tester.tcp_connectivity? }.to output(
          a_string_matching(/1\.1\.1\.1:53.*8\.8\.8\.8:53.*208\.67\.222\.222:53/)
        ).to_stdout
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns false when all endpoints fail' do
        expect(tester.tcp_connectivity?).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        allow(Socket).to receive(:tcp).and_yield
      end

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end
  end

  describe '#dns_working?' do

    context 'with verbose mode enabled' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: true) }

      before do
        allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
      end

      it 'outputs domain list to stdout' do
        expect { tester.dns_working? }.to output(
          a_string_matching(/Testing DNS resolution for domains: .*\.com/)
        ).to_stdout
      end
    end

    context 'with mocked failures' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
        allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
      end

      it 'returns false when all domains fail to resolve' do
        expect(tester.dns_working?).to be false
      end
    end

    context 'with mocked success' do
      let(:tester) { WifiWand::NetworkConnectivityTester.new(verbose: false) }

      before do
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