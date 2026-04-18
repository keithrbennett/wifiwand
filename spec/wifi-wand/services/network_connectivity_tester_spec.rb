# frozen_string_literal: true

require_relative '../../spec_helper'
require 'rbconfig'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  include TestHelpers

  let(:ruby_bin) { RbConfig.ruby }

  # These helpers build tiny child-process commands so the specs can exercise the
  # subprocess orchestration path directly: one reports success, one reports
  # failure, and one simulates a helper that never returns before the deadline.
  def helper_command(body)
    [ruby_bin, '-rjson', '-e', body]
  end

  def success_command
    helper_command('STDOUT.write(JSON.generate(success: true))')
  end

  def failure_command
    helper_command('STDOUT.write(JSON.generate(success: false, error_class: "RuntimeError"))')
  end

  def hanging_command
    [ruby_bin, '-e', 'sleep 10']
  end

  shared_examples 'subprocess-based cancellation' do
    |method_name:, items_method:, success_items:, failing_items:|
    let(:tester) { described_class.new(verbose: false) }

    it 'returns early when another helper succeeds before a hung helper finishes' do
      allow(tester).to receive(items_method).and_return(success_items)
      allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
        item == success_items.last ? success_command : hanging_command
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(tester.public_send(method_name)).to be true
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 0.5
    end

    it 'returns false within the documented deadline when a helper never returns' do
      allow(tester).to receive(items_method).and_return(failing_items)
      allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
        item == failing_items.last ? failure_command : hanging_command
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(tester.public_send(method_name)).to be false
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < (WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT + 0.2)
    end
  end

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

    context 'with helper-reported failures' do
      let(:tester) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { host: 'failed-a.test', port: 443 },
          { host: 'failed-b.test', port: 443 },
        ]
      end

      before do
        allow(tester).to receive_messages(tcp_test_endpoints: endpoints,
          connectivity_probe_command: failure_command)
      end

      it 'returns false when all endpoints fail' do
        result = Timeout.timeout(0.2) { tester.tcp_connectivity? }
        expect(result).to be false
      end
    end

    context 'with helper-reported success' do
      let(:tester) { described_class.new(verbose: false) }
      let(:endpoints) do
        [
          { host: 'failed.test', port: 443 },
          { host: 'success.test', port: 443 },
        ]
      end

      before do
        allow(tester).to receive(:tcp_test_endpoints).and_return(endpoints)
        allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
          item == endpoints.last ? success_command : failure_command
        end
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
        allow(tester).to receive(:tcp_test_endpoints).and_return(endpoints)
        allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
          item[:port] == 443 ? success_command : failure_command
        end
      end

      it 'still reports connectivity when an alternate port succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end
    end

    it_behaves_like 'subprocess-based cancellation',
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

      before { mock_dns_resolution_failure }

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end
    end

    context 'with helper-reported failures' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed-a.test failed-b.test] }

      before do
        allow(tester).to receive_messages(dns_test_domains: domains,
          connectivity_probe_command: failure_command)
      end

      it 'returns false when all domains fail to resolve' do
        result = Timeout.timeout(0.2) { tester.dns_working? }
        expect(result).to be false
      end
    end

    context 'with helper-reported success' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed.test success.test] }

      before do
        allow(tester).to receive(:dns_test_domains).and_return(domains)
        allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
          item == domains.last ? success_command : failure_command
        end
      end

      it 'returns true when at least one domain resolves' do
        expect(tester.dns_working?).to be true
      end
    end

    it_behaves_like 'subprocess-based cancellation',
      method_name:   :dns_working?,
      items_method:  :dns_test_domains,
      success_items: %w[hung.test success.test],
      failing_items: %w[hung.test failed.test]
  end

  describe '#fast_connectivity?' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns early when another fast helper succeeds before a hung helper finishes' do
      endpoints = [
        { host: 'hung.test', port: 443 },
        { host: 'success.test', port: 443 },
      ]
      allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
        item == endpoints.last ? success_command : hanging_command
      end
      allow(tester).to receive(:run_parallel_checks?).and_wrap_original do |original,
                                                                            _items,
                                                                            timeout,
                                                                            helper_mode:|
        original.call(endpoints, timeout, helper_mode: helper_mode)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(tester.fast_connectivity?).to be true
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 0.5
    end

    it 'returns false within the fast timeout when a helper never returns' do
      endpoints = [
        { host: 'hung.test', port: 443 },
        { host: 'failed.test', port: 443 },
      ]
      allow(tester).to receive(:connectivity_probe_command) do |item, _helper_mode|
        item == endpoints.last ? failure_command : hanging_command
      end
      allow(tester).to receive(:fast_connectivity?).and_call_original
      allow(tester).to receive(:run_parallel_checks?).and_wrap_original do |original,
                                                                            _items,
                                                                            timeout,
                                                                            helper_mode:|
        original.call(endpoints, timeout, helper_mode: helper_mode)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(tester.fast_connectivity?).to be false
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < (WifiWand::TimingConstants::FAST_CONNECTIVITY_TIMEOUT + 0.2)
    end
  end

  describe 'probe termination' do
    let(:tester) { described_class.new(verbose: false) }

    describe '#terminate_probe' do
      let(:reader) { instance_double(IO, closed?: false) }
      let(:probe) { { pid: 1234, reader: reader } }

      it 'sends TERM, waits for exit, and finalizes the probe' do
        allow(Process).to receive(:kill)
        allow(tester).to receive(:wait_for_probe_exit)
        allow(tester).to receive(:reap_probe)
        allow(reader).to receive(:close)

        tester.send(:terminate_probe, probe)

        expect(Process).to have_received(:kill).with('TERM', 1234).ordered
        expect(tester).to have_received(:wait_for_probe_exit).with(1234).ordered
        expect(reader).to have_received(:close)
        expect(tester).to have_received(:reap_probe).with(1234)
        expect(probe[:pid]).to be_nil
      end

      it 'swallows ESRCH races and still finalizes the probe' do
        allow(Process).to receive(:kill).with('TERM', 1234).and_raise(Errno::ESRCH)
        allow(tester).to receive(:reap_probe)
        allow(reader).to receive(:close)

        expect { tester.send(:terminate_probe, probe) }.not_to raise_error
        expect(reader).to have_received(:close)
        expect(tester).to have_received(:reap_probe).with(1234)
        expect(probe[:pid]).to be_nil
      end
    end

    describe '#wait_for_probe_exit' do
      it 'returns after a prompt reap without escalating to KILL' do
        allow(tester).to receive(:reap_probe).with(1234).and_return(1234)
        allow(Process).to receive(:kill)

        tester.send(:wait_for_probe_exit, 1234)

        expect(Process).not_to have_received(:kill).with('KILL', 1234)
      end

      it 'escalates to KILL when the probe misses the grace window' do
        monotonic_times = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05]
        allow(Process).to receive(:clock_gettime)
          .with(Process::CLOCK_MONOTONIC)
          .and_return(*monotonic_times)
        allow(tester).to receive(:sleep)
        allow(tester).to receive(:reap_probe).with(1234).and_return(nil, nil, nil, nil, nil, 1234)
        allow(Process).to receive(:kill)

        tester.send(:wait_for_probe_exit, 1234)

        expect(Process).to have_received(:kill).with('KILL', 1234)
        expect(tester).to have_received(:reap_probe).with(1234).exactly(6).times
      end
    end
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
