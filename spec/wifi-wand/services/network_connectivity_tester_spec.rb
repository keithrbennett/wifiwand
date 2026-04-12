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

    context 'when one endpoint succeeds before another blocking endpoint times out' do
      let(:tester) { described_class.new(verbose: false) }
      let(:slow_endpoint_events) { Queue.new }

      before do
        allow(tester).to receive(:tcp_test_endpoints).and_return([
          { host: 'slow.test', port: 443 },
          { host: 'fast.test', port: 443 },
        ])

        allow(Socket).to receive(:tcp) do |host, _port, connect_timeout:, &block|
          case host
          when 'slow.test'
            begin
              sleep(connect_timeout * 3)
              raise Errno::ETIMEDOUT
            ensure
              slow_endpoint_events << :slow_finished
            end
          when 'fast.test'
            block ? block.call : true
          else
            raise "Unexpected host: #{host}"
          end
        end
      end

      it 'returns promptly after the first successful connection' do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect(tester.tcp_connectivity?).to be true
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        expect(elapsed).to be < (WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT / 2.0)
      end

      it 'allows slower checks to finish naturally after returning early' do
        expect(tester.tcp_connectivity?).to be true

        expect(slow_endpoint_events.pop(timeout: 1)).to eq(:slow_finished)
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

  describe '#internet_connectivity_state' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns :reachable when TCP, DNS, and captive portal check all pass' do
      allow(tester).to receive_messages(
        tcp_connectivity?:    true,
        dns_working?:         true,
        captive_portal_state: :free,
      )

      expect(tester.internet_connectivity_state).to eq(:reachable)
    end

    it 'returns :unreachable when TCP fails' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: true)

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :unreachable when DNS fails' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: false)

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :unreachable when both TCP and DNS fail' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: false)

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :unreachable when captive portal is detected' do
      allow(tester).to receive_messages(
        tcp_connectivity?:    true,
        dns_working?:         true,
        captive_portal_state: :present,
      )

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :indeterminate when TCP and DNS pass but captive portal status is indeterminate' do
      allow(tester).to receive_messages(
        tcp_connectivity?:    true,
        dns_working?:         true,
        captive_portal_state: :indeterminate,
      )

      expect(tester.internet_connectivity_state).to eq(:indeterminate)
    end

    it 'skips captive portal check when TCP fails (short-circuit)' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_state)

      tester.internet_connectivity_state
    end

    it 'accepts a pre-computed captive portal state and does not re-check' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_state)

      expect(tester.internet_connectivity_state(true, true, :free)).to eq(:reachable)
    end

    it 'preserves a pre-computed indeterminate captive portal state' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_state)

      expect(tester.internet_connectivity_state(true, true, :indeterminate)).to eq(:indeterminate)
    end
  end

  describe '#captive_portal_state' do
    let(:tester) { described_class.new(verbose: false) }

    it 'delegates to the captive_portal_checker' do
      checker = tester.captive_portal_checker
      allow(checker).to receive(:captive_portal_state).and_return(:free)
      expect(tester.captive_portal_state).to eq(:free)
    end

    context 'when the connectivity check endpoint returns 204' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_state).and_return(:free)
      end

      it 'returns :free' do
        expect(tester.captive_portal_state).to eq(:free)
      end
    end

    context 'when the connectivity check endpoint returns a redirect (captive portal)' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_state).and_return(:present)
      end

      it 'returns :present' do
        expect(tester.captive_portal_state).to eq(:present)
      end
    end

    context 'when all HTTP requests fail with network errors' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_state).and_return(:indeterminate)
      end

      it 'returns :indeterminate' do
        expect(tester.captive_portal_state).to eq(:indeterminate)
      end
    end

    context 'with verbose mode' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_state) do
          output.puts 'Testing captive portal via HTTP: http://example.com/check'
          output.puts 'Captive portal check http://example.com/check: HTTP 204 (expected 204) -> pass'
          output.puts 'Captive portal results: [:free] -- free'
          :free
        end
      end

      it 'logs the endpoints being checked' do
        tester.captive_portal_state
        expect(output.string).to match(/Testing captive portal via HTTP:/)
      end

      it 'logs a pass result' do
        tester.captive_portal_state
        expect(output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal detected' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_state) do
          output.puts 'Captive portal check http://example.com/check: HTTP 302 (expected 204) -> mismatch'
          output.puts 'Captive portal results: [:present] -- detected'
          :present
        end
      end

      it 'logs results array and detected status' do
        tester.captive_portal_state
        expect(output.string).to include('mismatch')
        expect(output.string).to include('detected')
      end
    end
  end
end
