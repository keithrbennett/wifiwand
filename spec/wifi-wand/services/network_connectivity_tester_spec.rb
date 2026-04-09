# frozen_string_literal: true

require_relative '../../spec_helper'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  include TestHelpers

  describe '#tcp_connectivity?' do
    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

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
      let(:tester) { described_class.new(verbose: false) }

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
      let(:tester) { described_class.new(verbose: false) }

      before { mock_socket_connection_success }

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end

    context 'when some ports are blocked but others remain open' do
      let(:tester) { described_class.new(verbose: false) }

      before do
        allow(tester).to receive(:tcp_test_endpoints).and_return([
          { host: '1.1.1.1', port: 53 },
          { host: '1.1.1.1', port: 443 },
        ])

        allow(Socket).to receive(:tcp) do |_host, port, connect_timeout:, &block|
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
      let(:tester) { described_class.new(verbose: true, output: output) }

      before { mock_dns_resolution_failure }

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end
    end

    context 'with mocked failures' do
      let(:tester) { described_class.new(verbose: false) }

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
      let(:tester) { described_class.new(verbose: false) }

      before { mock_dns_resolution_success }

      it 'returns true when at least one domain resolves' do
        expect(tester.dns_working?).to be true
      end
    end
  end

  describe '#connected_to_internet?' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns true when TCP, DNS, and captive portal check all pass' do
      allow(tester).to receive_messages(
        tcp_connectivity?: true,
        dns_working?: true,
        captive_portal_free?: true,
      )

      expect(tester.connected_to_internet?).to be true
    end

    it 'returns false when TCP fails' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: true)

      expect(tester.connected_to_internet?).to be false
    end

    it 'returns false when DNS fails' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: false)

      expect(tester.connected_to_internet?).to be false
    end

    it 'returns false when both TCP and DNS fail' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: false)

      expect(tester.connected_to_internet?).to be false
    end

    it 'returns false when captive portal is detected (TCP and DNS pass but portal intercepts)' do
      allow(tester).to receive_messages(
        tcp_connectivity?: true,
        dns_working?: true,
        captive_portal_free?: false,
      )

      expect(tester.connected_to_internet?).to be false
    end

    it 'skips captive portal check when TCP fails (short-circuit)' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_free?)

      tester.connected_to_internet?
    end

    it 'accepts pre-computed captive_free value and does not re-check' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_free?)

      expect(tester.connected_to_internet?(true, true, true)).to be true
    end
  end

  describe '#captive_portal_free?' do
    let(:tester) { described_class.new(verbose: false) }

    it 'delegates to the captive_portal_checker' do
      checker = tester.captive_portal_checker
      allow(checker).to receive(:captive_portal_free?).and_return(true)
      expect(tester.captive_portal_free?).to be true
    end

    context 'when the connectivity check endpoint returns 204' do
      before { mock_captive_portal_free }

      it 'returns true' do
        expect(tester.captive_portal_free?).to be true
      end
    end

    context 'when the connectivity check endpoint returns a redirect (captive portal)' do
      before { mock_captive_portal_detected }

      it 'returns false' do
        expect(tester.captive_portal_free?).to be false
      end
    end

    context 'when all HTTP requests fail with network errors' do
      before do
        stub_short_connectivity_timeouts
        allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns true (assumes free to avoid false negatives)' do
        expect(tester.captive_portal_free?).to be true
      end
    end

    context 'with verbose mode' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before { mock_captive_portal_free }

      it 'logs the endpoints being checked' do
        tester.captive_portal_free?
        expect(output.string).to match(/Testing captive portal via HTTP:/)
      end

      it 'logs a pass result' do
        tester.captive_portal_free?
        expect(output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal detected' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before { mock_captive_portal_detected }

      it 'logs results array and detected status' do
        tester.captive_portal_free?
        expect(output.string).to include('mismatch')
        expect(output.string).to include('detected')
      end
    end
  end
end
