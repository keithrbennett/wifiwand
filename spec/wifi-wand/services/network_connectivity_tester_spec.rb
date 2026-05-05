# frozen_string_literal: true

require_relative '../../spec_helper'
require 'rbconfig'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  include TestHelpers

  let(:ruby_bin) { RbConfig.ruby }

  def helper_command(body)
    [ruby_bin, '-rjson', '-e', body]
  end

  def json_payload_command(payload)
    helper_command("STDOUT.write(#{JSON.generate(payload).inspect})")
  end

  def success_command
    helper_command('STDOUT.write(JSON.generate(success: true, timed_out: false))')
  end

  def failure_command
    helper_command(
      'STDOUT.write(JSON.generate(success: false, timed_out: false, error_class: "RuntimeError"))'
    )
  end

  def hanging_command
    [ruby_bin, '-e', 'sleep 10']
  end

  def expect_false_without_hanging(timeout: 1.0)
    result = nil
    Timeout.timeout(timeout) { result = yield }
    expect(result).to be false
  end

  shared_examples 'single helper process cancellation' do
    |method_name:, items_method:, success_items:, failing_items:|
    let(:tester) { described_class.new(verbose: false) }

    it 'returns true when the helper reports that any probe succeeded' do
      observed_batches = []
      allow(tester).to receive(items_method).and_return(success_items)
      allow(tester).to receive(:connectivity_probe_command) do |items, _helper_mode, _overall_timeout|
        observed_batches << items
        success_command
      end

      result = nil
      Timeout.timeout(1) { result = tester.public_send(method_name) }

      expect(result).to be true
      expect(observed_batches).to eq([success_items])
    end

    it 'returns a timed-out result when the helper misses the overall timeout' do
      allow(tester).to receive(items_method).and_return(failing_items)
      allow(tester).to receive(:connectivity_probe_command).and_return(hanging_command)

      result = nil
      Timeout.timeout(1) do
        result = tester.public_send(method_name, overall_timeout: 0.05, return_details: true)
      end

      expect(result).to eq(success: false, timed_out: true)
    end
  end

  describe '#tcp_connectivity?' do
    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester).to receive(:connectivity_probe_command).and_return(failure_command)
      end

      it 'outputs formatted endpoint list to stdout' do
        tester.tcp_connectivity?
        expect(output.string).to match(/Testing internet TCP connectivity to: .*:.*/)
      end

      it 'formats endpoints as host:port pairs separated by commas' do
        tester.tcp_connectivity?
        expect(output.string).to match(/1\.1\.1\.1:443.*8\.8\.8\.8:443.*208\.67\.222\.222:443/)
      end

      it 'logs helper-reported probe failures to the configured output' do
        probe_command = json_payload_command(
          success:       false,
          timed_out:     false,
          probe_results: [
            {
              target:      { host: 'failed.test', port: 443 },
              success:     false,
              error_class: 'SocketError',
            },
          ]
        )
        allow(tester).to receive_messages(
          tcp_test_endpoints:         [{ host: 'failed.test', port: 443 }],
          connectivity_probe_command: probe_command
        )

        tester.tcp_connectivity?

        expect(output.string).to include('Failed to connect to failed.test:443: SocketError')
      end

      it 'logs helper-reported probe successes to the configured output' do
        probe_command = json_payload_command(
          success:       true,
          timed_out:     false,
          probe_results: [
            {
              target:      { host: 'success.test', port: 443 },
              success:     true,
              error_class: nil,
            },
          ]
        )
        allow(tester).to receive_messages(
          tcp_test_endpoints:         [{ host: 'success.test', port: 443 }],
          connectivity_probe_command: probe_command
        )

        tester.tcp_connectivity?

        expect(output.string).to include('Successfully connected to success.test:443')
      end
    end

    context 'when TCP probes fail' do
      let(:tester) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { host: 'failed-a.test', port: 443 },
          { host: 'failed-b.test', port: 443 },
        ]
      end

      before do
        allow(tester).to receive_messages(
          tcp_test_endpoints:         endpoints,
          connectivity_probe_command: failure_command
        )
      end

      it 'returns false when all endpoints fail' do
        expect_false_without_hanging { tester.tcp_connectivity? }
      end
    end

    context 'when a TCP probe succeeds' do
      let(:tester) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { host: 'failed.test', port: 443 },
          { host: 'success.test', port: 443 },
        ]
      end

      before do
        allow(tester).to receive_messages(
          tcp_test_endpoints:         endpoints,
          connectivity_probe_command: success_command
        )
      end

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end

    context 'when some ports are blocked but others remain open' do
      let(:tester) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { host: '1.1.1.1', port: 53 },
          { host: '1.1.1.1', port: 443 },
        ]
      end

      before do
        allow(tester).to receive_messages(
          tcp_test_endpoints:         endpoints,
          connectivity_probe_command: success_command
        )
      end

      it 'still reports connectivity when an alternate port succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end

    it_behaves_like 'single helper process cancellation',
      method_name:   :tcp_connectivity?,
      items_method:  :tcp_test_endpoints,
      success_items: [
        { host: 'hung.test', port: 443 },
        { host: 'success.test', port: 443 },
      ],
      failing_items: [
        { host: 'hung.test', port: 443 },
        { host: 'failed.test', port: 443 },
      ]
  end

  describe '#dns_working?' do
    context 'with verbose mode enabled' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester).to receive(:connectivity_probe_command).and_return(failure_command)
      end

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end

      it 'logs helper-reported probe failures to the configured output' do
        probe_command = json_payload_command(
          success:       false,
          timed_out:     false,
          probe_results: [
            {
              target:      'failed.test',
              success:     false,
              error_class: 'SocketError',
            },
          ]
        )
        allow(tester).to receive_messages(
          dns_test_domains:           ['failed.test'],
          connectivity_probe_command: probe_command
        )

        tester.dns_working?

        expect(output.string).to include('Failed to resolve failed.test: SocketError')
      end

      it 'logs helper-reported probe successes to the configured output' do
        probe_command = json_payload_command(
          success:       true,
          timed_out:     false,
          probe_results: [
            {
              target:      'success.test',
              success:     true,
              error_class: nil,
            },
          ]
        )
        allow(tester).to receive_messages(
          dns_test_domains:           ['success.test'],
          connectivity_probe_command: probe_command
        )

        tester.dns_working?

        expect(output.string).to include('Successfully resolved success.test')
      end
    end

    context 'when DNS probes fail' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed-a.test failed-b.test] }

      before do
        allow(tester).to receive_messages(
          dns_test_domains:           domains,
          connectivity_probe_command: failure_command
        )
      end

      it 'returns false when all domains fail to resolve' do
        expect_false_without_hanging { tester.dns_working? }
      end
    end

    context 'when a DNS probe succeeds' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed.test success.test] }

      before do
        allow(tester).to receive_messages(
          dns_test_domains:           domains,
          connectivity_probe_command: success_command
        )
      end

      it 'returns true when at least one domain resolves' do
        expect(tester.dns_working?).to be true
      end
    end

    it_behaves_like 'single helper process cancellation',
      method_name:   :dns_working?,
      items_method:  :dns_test_domains,
      success_items: %w[hung.test success.test],
      failing_items: %w[hung.test failed.test]
  end

  describe '#internet_connectivity_state' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns :reachable when TCP, DNS, and captive portal check all pass' do
      allow(tester).to receive_messages(
        tcp_connectivity?:    true,
        dns_working?:         true,
        captive_portal_state: :free
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
        captive_portal_state: :present
      )

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :indeterminate when TCP and DNS pass but captive portal status is indeterminate' do
      allow(tester).to receive_messages(
        tcp_connectivity?:    true,
        dns_working?:         true,
        captive_portal_state: :indeterminate
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

    it 'returns :indeterminate when the caller timeout expires during TCP probing' do
      allow(tester).to receive(:current_time).and_return(100.0, 100.0, 100.0, 100.05)
      expect(tester).to receive(:tcp_connectivity?).with(
        hash_including(
          overall_timeout: be_within(0.001).of(0.05),
          return_details:  true
        )
      ).and_return(success: false, timed_out: true)
      expect(tester).not_to receive(:dns_working?)
      expect(tester).not_to receive(:captive_portal_state)

      expect(tester.internet_connectivity_state(timeout_in_secs: 0.05)).to eq(:indeterminate)
    end

    it 'returns :indeterminate when the caller timeout expires before captive portal probing' do
      allow(tester).to receive(:current_time).and_return(100.0, 100.0, 100.0, 100.0, 100.025, 100.025, 100.05)
      expect(tester).to receive(:tcp_connectivity?).with(
        hash_including(
          overall_timeout: be_within(0.001).of(0.05),
          return_details:  true
        )
      ).and_return(success: true, timed_out: false)
      expect(tester).to receive(:dns_working?).with(
        hash_including(
          overall_timeout: be_within(0.001).of(0.025),
          return_details:  true
        )
      ).and_return(success: false, timed_out: true)
      expect(tester).not_to receive(:captive_portal_state)

      expect(tester.internet_connectivity_state(timeout_in_secs: 0.05)).to eq(:indeterminate)
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
