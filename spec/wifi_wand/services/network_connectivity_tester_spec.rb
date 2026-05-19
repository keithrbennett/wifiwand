# frozen_string_literal: true

require_relative '../../spec_helper'
require 'rbconfig'
require 'stringio'
require_relative '../../../lib/wifi_wand/services/network_connectivity_tester'

describe WifiWand::NetworkConnectivityTester do
  include TestHelpers

  let(:open_probe_writers) { [] }

  def completed_connectivity_probe(helper_mode:, payload:)
    reader, writer = IO.pipe
    writer.write(JSON.generate(payload))
    writer.close
    { pid: nil, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def open_connectivity_probe(helper_mode:, payload:)
    reader, writer = IO.pipe
    writer.write(JSON.generate(payload))
    writer.flush
    open_probe_writers << writer
    { pid: nil, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def pending_connectivity_probe(helper_mode:)
    reader, writer = IO.pipe
    open_probe_writers << writer
    { pid: nil, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def raw_connectivity_probe(helper_mode:, output:)
    reader, writer = IO.pipe
    writer.write(output)
    writer.close
    { pid: nil, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }
  rescue IOError, SystemCallError
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def with_probe_io(pid: 12_345, helper_mode: :tcp)
    reader, writer = IO.pipe
    writer.close
    probe = { pid: pid, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }

    yield reader, writer, probe
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  def successful_probe_payload
    { success: true, timed_out: false }
  end

  def failing_probe_payload
    { success: false, timed_out: false, error_class: 'RuntimeError' }
  end

  def expect_false_without_hanging(timeout: 1.0)
    result = nil
    Timeout.timeout(timeout) { result = yield }
    expect(result).to be false
  end

  after do
    open_probe_writers.each do |writer|
      writer.close unless writer.closed?
    end
  end

  shared_examples 'single helper process cancellation' do
    |method_name:, items_method:, success_items:, failing_items:|
    let(:tester) { described_class.new(verbose: false) }

    it 'returns true when the helper reports that any probe succeeded' do
      observed_batches = []
      allow(tester).to receive(items_method).and_return(success_items)
      allow(tester).to receive(:start_connectivity_probe) do |items, helper_mode, _overall_timeout|
        observed_batches << items
        completed_connectivity_probe(helper_mode: helper_mode, payload: successful_probe_payload)
      end

      result = nil
      Timeout.timeout(1) { result = tester.public_send(method_name) }

      expect(result).to be true
      expect(observed_batches).to eq([success_items])
    end

    it 'returns a timed-out result when the helper misses the overall timeout' do
      allow(tester).to receive(items_method).and_return(failing_items)
      allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
        pending_connectivity_probe(helper_mode: helper_mode)
      end

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
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: failing_probe_payload)
        end
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
        probe_payload = {
          success:       false,
          timed_out:     false,
          probe_results: [
            {
              target:      { host: 'failed.test', port: 443 },
              success:     false,
              error_class: 'SocketError',
            },
          ],
        }
        allow(tester).to receive(:tcp_test_endpoints).and_return([{ host: 'failed.test', port: 443 }])
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: probe_payload)
        end

        tester.tcp_connectivity?

        expect(output.string).to include('Failed to connect to failed.test:443: SocketError')
      end

      it 'logs helper-reported probe successes to the configured output' do
        probe_payload = {
          success:       true,
          timed_out:     false,
          probe_results: [
            {
              target:      { host: 'success.test', port: 443 },
              success:     true,
              error_class: nil,
            },
          ],
        }
        allow(tester).to receive(:tcp_test_endpoints).and_return([{ host: 'success.test', port: 443 }])
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: probe_payload)
        end

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
        allow(tester).to receive(:tcp_test_endpoints).and_return(endpoints)
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: failing_probe_payload)
        end
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
        allow(tester).to receive(:tcp_test_endpoints).and_return(endpoints)
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: successful_probe_payload)
        end
      end

      it 'returns true when at least one endpoint succeeds' do
        expect(tester.tcp_connectivity?).to be true
      end

      it 'returns parsed details before a successful helper closes stdout' do
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          open_connectivity_probe(helper_mode: helper_mode, payload: successful_probe_payload)
        end

        result = nil
        Timeout.timeout(1) do
          result = tester.tcp_connectivity?(overall_timeout: 0.5, return_details: true)
        end

        expect(result).to eq(success: true, timed_out: false)
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
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: successful_probe_payload)
        end
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
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: failing_probe_payload)
        end
      end

      it 'outputs domain list to stdout' do
        tester.dns_working?
        expect(output.string).to match(/Testing DNS resolution for domains: .*\.com/)
      end

      it 'logs helper-reported probe failures to the configured output' do
        probe_payload = {
          success:       false,
          timed_out:     false,
          probe_results: [
            {
              target:      'failed.test',
              success:     false,
              error_class: 'SocketError',
            },
          ],
        }
        allow(tester).to receive(:dns_test_domains).and_return(['failed.test'])
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: probe_payload)
        end

        tester.dns_working?

        expect(output.string).to include('Failed to resolve failed.test: SocketError')
      end

      it 'logs helper-reported probe successes to the configured output' do
        probe_payload = {
          success:       true,
          timed_out:     false,
          probe_results: [
            {
              target:      'success.test',
              success:     true,
              error_class: nil,
            },
          ],
        }
        allow(tester).to receive(:dns_test_domains).and_return(['success.test'])
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: probe_payload)
        end

        tester.dns_working?

        expect(output.string).to include('Successfully resolved success.test')
      end
    end

    context 'when DNS probes fail' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed-a.test failed-b.test] }

      before do
        allow(tester).to receive(:dns_test_domains).and_return(domains)
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: failing_probe_payload)
        end
      end

      it 'returns false when all domains fail to resolve' do
        expect_false_without_hanging { tester.dns_working? }
      end
    end

    context 'when a DNS probe succeeds' do
      let(:tester) { described_class.new(verbose: false) }
      let(:domains) { %w[failed.test success.test] }

      before do
        allow(tester).to receive(:dns_test_domains).and_return(domains)
        allow(tester).to receive(:start_connectivity_probe) do |_items, helper_mode, _overall_timeout|
          completed_connectivity_probe(helper_mode: helper_mode, payload: successful_probe_payload)
        end
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

  describe '#start_connectivity_probe' do
    let(:tester) { described_class.new(verbose: false) }
    let(:items) { [{ host: 'example.test', port: 443 }] }

    it 'starts a helper process and returns the reader metadata' do
      reader, writer = IO.pipe
      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_return(12_345)

      probe = tester.send(:start_connectivity_probe, items, :tcp, 0.25)

      expect(Process).to have_received(:spawn).with(
        RbConfig.ruby,
        end_with('network_connectivity_probe_helper.rb'),
        'tcp',
        JSON.generate(items),
        '0.25',
        out: writer,
        err: File::NULL
      )
      expect(probe).to include(pid: 12_345, reader: reader, helper_mode: :tcp, buffer: +'')
      expect(probe[:eof]).to be(false)
      expect(writer).to be_closed
    ensure
      reader&.close unless reader&.closed?
    end

    it 'returns nil, closes pipes, and logs when spawn fails' do
      output = StringIO.new
      tester = described_class.new(verbose: true, output: output)
      reader, writer = IO.pipe
      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_raise(Errno::EAGAIN)

      expect(tester.send(:start_connectivity_probe, items, :tcp, 0.25)).to be_nil
      expect(reader).to be_closed
      expect(writer).to be_closed
      expect(output.string).to include('Failed to start tcp connectivity helper: Errno::EAGAIN')
    end

    it 'terminates the helper and closes pipes when setup fails after spawn' do
      reader, writer = IO.pipe
      original_writer_close = writer.method(:close)
      writer_close_calls = 0

      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_return(12_345)
      allow(Process).to receive(:kill)
      allow(tester).to receive(:wait_for_probe_exit).and_return(true)
      allow(writer).to receive(:close) do
        writer_close_calls += 1
        raise IOError, 'close failed' if writer_close_calls == 1

        original_writer_close.call
      end

      expect(tester.send(:start_connectivity_probe, items, :tcp, 0.25)).to be_nil
      expect(Process).to have_received(:kill).with('TERM', 12_345)
      expect(tester).to have_received(:wait_for_probe_exit).with(12_345, grace: 0)
      expect(reader).to be_closed
      expect(writer).to be_closed
    end

    it 'still terminates the helper and closes the writer when reader cleanup fails' do
      reader, writer = IO.pipe
      original_reader_close = reader.method(:close)
      original_reader_closed = reader.method(:closed?)
      original_writer_close = writer.method(:close)
      writer_close_calls = 0

      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_return(12_345)
      allow(Process).to receive(:kill)
      allow(tester).to receive(:wait_for_probe_exit).and_return(true)
      allow(reader).to receive(:closed?).and_return(false)
      allow(reader).to receive(:close).and_raise(IOError, 'reader close failed')
      allow(writer).to receive(:close) do
        writer_close_calls += 1
        raise IOError, 'writer close failed' if writer_close_calls == 1

        original_writer_close.call
      end

      expect(tester.send(:start_connectivity_probe, items, :tcp, 0.25)).to be_nil
      expect(Process).to have_received(:kill).with('TERM', 12_345)
      expect(tester).to have_received(:wait_for_probe_exit).with(12_345, grace: 0)
      expect(writer).to be_closed
    ensure
      original_reader_close.call if original_reader_closed && !original_reader_closed.call
    end

    it 'clears the helper pid when the process is already gone during cleanup' do
      with_probe_io do |reader, _writer, probe|
        allow(Process).to receive(:kill).with('TERM', 12_345).and_raise(Errno::ESRCH)

        expect { tester.send(:cleanup_failed_connectivity_probe_process, probe) }.not_to raise_error
        expect(probe[:pid]).to be_nil
        expect(reader).to be_closed
      end
    end

    it 'suppresses system call failures during failed helper cleanup' do
      with_probe_io do |reader, _writer, probe|
        allow(Process).to receive(:kill).with('TERM', 12_345).and_raise(Errno::EPERM)

        expect { tester.send(:cleanup_failed_connectivity_probe_process, probe) }.not_to raise_error
        expect(reader).to be_closed
      end
    end
  end

  describe '#read_probe_result' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns a failed helper result when the helper closes stdout without output' do
      probe = raw_connectivity_probe(helper_mode: :tcp, output: '')

      expect(tester.send(:read_probe_result, probe)).to eq(
        success:       false,
        timed_out:     false,
        error_class:   'EOFError',
        probe_results: []
      )
    ensure
      probe&.fetch(:reader)&.close unless probe&.fetch(:reader)&.closed?
    end

    it 'returns a failed helper result when closed helper output is malformed JSON' do
      probe = raw_connectivity_probe(helper_mode: :tcp, output: 'not json {{{')

      expect(tester.send(:read_probe_result, probe)).to eq(
        success:       false,
        timed_out:     false,
        error_class:   'JSON::ParserError',
        probe_results: []
      )
    ensure
      probe&.fetch(:reader)&.close unless probe&.fetch(:reader)&.closed?
    end
  end

  describe '#internet_connectivity_state' do
    let(:tester) { described_class.new(verbose: false) }

    it 'returns :reachable when TCP, DNS, and captive portal check all pass' do
      allow(tester).to receive_messages(
        tcp_connectivity?:             true,
        dns_working?:                  true,
        captive_portal_login_required: :no
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
        tcp_connectivity?:             true,
        dns_working?:                  true,
        captive_portal_login_required: :yes
      )

      expect(tester.internet_connectivity_state).to eq(:unreachable)
    end

    it 'returns :indeterminate when TCP and DNS pass but captive portal login requirement is unknown' do
      allow(tester).to receive_messages(
        tcp_connectivity?:             true,
        dns_working?:                  true,
        captive_portal_login_required: :unknown
      )

      expect(tester.internet_connectivity_state).to eq(:indeterminate)
    end

    it 'skips captive portal check when TCP fails (short-circuit)' do
      allow(tester).to receive_messages(tcp_connectivity?: false, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_login_required)

      tester.internet_connectivity_state
    end

    it 'accepts a pre-computed captive portal login requirement and does not re-check' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_login_required)

      expect(tester.internet_connectivity_state(true, true, :no)).to eq(:reachable)
    end

    it 'preserves a pre-computed unknown captive portal login requirement as indeterminate connectivity' do
      allow(tester).to receive_messages(tcp_connectivity?: true, dns_working?: true)
      expect(tester).not_to receive(:captive_portal_login_required)

      expect(tester.internet_connectivity_state(true, true, :unknown)).to eq(:indeterminate)
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
      expect(tester).not_to receive(:captive_portal_login_required)

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
      expect(tester).not_to receive(:captive_portal_login_required)

      expect(tester.internet_connectivity_state(timeout_in_secs: 0.05)).to eq(:indeterminate)
    end
  end

  describe '#captive_portal_login_required' do
    let(:tester) { described_class.new(verbose: false) }

    it 'delegates to the captive_portal_checker' do
      checker = tester.captive_portal_checker
      allow(checker).to receive(:captive_portal_login_required).and_return(:no)
      expect(tester.captive_portal_login_required).to eq(:no)
    end

    context 'when the connectivity check endpoint returns 204' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_login_required).and_return(:no)
      end

      it 'returns :no' do
        expect(tester.captive_portal_login_required).to eq(:no)
      end
    end

    context 'when the connectivity check endpoint returns a redirect (captive portal)' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_login_required).and_return(:yes)
      end

      it 'returns :yes' do
        expect(tester.captive_portal_login_required).to eq(:yes)
      end
    end

    context 'when all HTTP requests fail with network errors' do
      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_login_required).and_return(:unknown)
      end

      it 'returns :unknown' do
        expect(tester.captive_portal_login_required).to eq(:unknown)
      end
    end

    context 'with verbose mode' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_login_required) do
          output.puts 'Testing captive portal via HTTP: http://example.com/check'
          output.puts 'Captive portal check http://example.com/check: HTTP 204 (expected 204) -> pass'
          output.puts 'Captive portal results: [:no] -- no'
          :no
        end
      end

      it 'logs the endpoints being checked' do
        tester.captive_portal_login_required
        expect(output.string).to match(/Testing captive portal via HTTP:/)
      end

      it 'logs a pass result' do
        tester.captive_portal_login_required
        expect(output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal login required' do
      let(:output) { StringIO.new }
      let(:tester) { described_class.new(verbose: true, output: output) }

      before do
        allow(tester.captive_portal_checker).to receive(:captive_portal_login_required) do
          output.puts 'Captive portal check http://example.com/check: HTTP 302 (expected 204) -> mismatch'
          output.puts 'Captive portal results: [:yes] -- required'
          :yes
        end
      end

      it 'logs results array and required status' do
        tester.captive_portal_login_required
        expect(output.string).to include('mismatch')
        expect(output.string).to include('required')
      end
    end
  end
end
