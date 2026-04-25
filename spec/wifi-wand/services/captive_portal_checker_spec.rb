# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'rbconfig'
require 'socket'
require 'stringio'
require_relative '../../../lib/wifi-wand/services/captive_portal_checker'

describe WifiWand::CaptivePortalChecker do
  include TestHelpers

  describe '#captive_portal_state' do
    let(:checker) { described_class.new(verbose: false) }
    let(:spawned_pids) { [] }
    let(:endpoints) do
      [
        { url: 'http://first.example.com/check', expected_code: 204 },
        { url: 'http://second.example.com/check', expected_code: 204 },
      ]
    end

    after do
      spawned_pids.each do |pid|
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
        nil
      ensure
        begin
          Process.wait(pid, Process::WNOHANG)
        rescue Errno::ECHILD
          nil
        end
      end
    end

    before do
      allow(checker).to receive(:captive_portal_check_endpoints).and_return(endpoints)
    end

    it 'returns :free when any helper reports a successful endpoint' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[present free])

      expect(checker.captive_portal_state).to eq(:free)
    end

    it 'returns :present when endpoints mismatch and none succeed' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[present indeterminate])

      expect(checker.captive_portal_state).to eq(:present)
    end

    it 'returns :indeterminate when every endpoint errors' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[indeterminate indeterminate])

      expect(checker.captive_portal_state).to eq(:indeterminate)
    end

    it 'returns promptly after a helper reports :free and terminates slower helpers' do
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        spawn_probe(endpoint: endpoints.first, payload: { state: 'free', actual_code: 204 }),
        spawn_probe(endpoint: endpoints.last, delay: 5)
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(checker.captive_portal_state).to eq(:free)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 1
      expect { Process.kill(0, spawned_pids.last) }.to raise_error(Errno::ESRCH)
    end

    it 'returns promptly when a helper writes partial JSON and then stalls' do
      stub_const('WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT', 0.1)
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        spawn_probe(endpoint: endpoints.first, raw_output: '{"state":"free"', post_write_delay: 5)
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(checker.captive_portal_state).to eq(:indeterminate)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 1
      expect { Process.kill(0, spawned_pids.last) }.to raise_error(Errno::ESRCH)
    end

    it 'does not expand a caller-provided timeout budget with helper grace' do
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        spawn_probe(endpoint: endpoints.first, delay: 5)
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(checker.captive_portal_state(timeout_in_secs: 0.05)).to eq(:indeterminate)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 0.2
    end

    context 'with verbose mode' do
      let(:output) { StringIO.new }
      let(:checker) { described_class.new(verbose: true, output: output) }

      before do
        allow(checker).to receive(:captive_portal_check_endpoints).and_return(endpoints)
      end

      it 'logs the endpoints being checked' do
        allow(checker).to receive(:captive_portal_results).and_return([:free])

        checker.captive_portal_state
        expect(output.string).to match(/Testing captive portal via HTTP:/)
      end

      it 'logs a pass result' do
        allow(checker).to receive(:start_captive_portal_probe).and_return(
          spawn_probe(endpoint: endpoints.first, payload: { state: 'free', actual_code: 204 })
        )

        checker.captive_portal_state
        expect(output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal detected' do
      let(:output) { StringIO.new }
      let(:checker) { described_class.new(verbose: true, output: output) }

      before do
        allow(checker).to receive_messages(
          captive_portal_check_endpoints: [endpoints.first],
          start_captive_portal_probe:     spawn_probe(
            endpoint: endpoints.first,
            payload:  { state: 'present', actual_code: 302 }
          )
        )
      end

      it 'logs results array and detected status' do
        checker.captive_portal_state
        expect(output.string).to include('mismatch')
        expect(output.string).to include('detected')
      end
    end
  end

  describe '#perform_captive_portal_check' do
    let(:checker) { described_class.new(verbose: false) }
    let(:endpoint) { { url: 'http://example.com/check', expected_code: 204 } }

    it 'returns :free metadata when the endpoint returns the expected code' do
      mock_captive_portal_free_state

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        state: :free, actual_code: 204
      )
    end

    it 'returns :present metadata when the endpoint returns a redirect' do
      mock_captive_portal_detected

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        state: :present, actual_code: 302
      )
    end

    it 'returns :free when both code and expected body match' do
      endpoint_with_body = {
        url:           'http://example.com/connecttest.txt',
        expected_code: 200,
        expected_body: 'Microsoft Connect Test',
      }
      mock_captive_portal_free_state(code: '200', body: 'Microsoft Connect Test')

      expect(checker.send(:perform_captive_portal_check, endpoint_with_body)).to eq(
        state: :free, actual_code: 200
      )
    end

    it 'returns :present when the code matches but the body does not' do
      endpoint_with_body = {
        url:           'http://example.com/connecttest.txt',
        expected_code: 200,
        expected_body: 'Microsoft Connect Test',
      }
      mock_captive_portal_detected(code: '200', body: '<html>Login</html>')

      expect(checker.send(:perform_captive_portal_check, endpoint_with_body)).to eq(
        state: :present, actual_code: 200
      )
    end

    it 'returns :indeterminate metadata on network errors' do
      stub_short_connectivity_timeouts
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        state: :indeterminate, error_class: 'Errno::ECONNREFUSED'
      )
    end
  end

  # ---------------------------------------------------------------------------
  # read_probe_result — malformed / unexpected subprocess output regression
  # ---------------------------------------------------------------------------
  describe '#read_probe_result' do
    let(:checker) { described_class.new(verbose: false) }

    # Build a probe backed by a real pipe so read_nonblock behavior matches production.
    def probe_with_output(text, close_writer: true)
      reader, writer = IO.pipe
      writer.write(text)
      writer.flush
      writer.close if close_writer
      {
        pid:      nil,
        reader:   reader,
        endpoint: { url: 'http://example.com', expected_code: 204 },
        buffer:   +'',
        eof:      false,
        writer:   close_writer ? nil : writer,
      }
    end

    it 'returns :indeterminate and records the error class for empty output' do
      result = checker.send(:read_probe_result, probe_with_output(''))
      expect(result[:state]).to eq(:indeterminate)
      expect(result[:error_class]).to be_a(String)
    end

    it 'returns :indeterminate and records the error class for malformed JSON' do
      result = checker.send(:read_probe_result, probe_with_output('not json {{{'))
      expect(result[:state]).to eq(:indeterminate)
      expect(result[:error_class]).to be_a(String)
    end

    it 'returns nil for partial JSON before EOF and fails only after EOF' do
      probe = probe_with_output('{"state":"free"', close_writer: false)

      expect(checker.send(:read_probe_result, probe)).to be_nil

      probe[:writer].close
      result = checker.send(:read_probe_result, probe)
      expect(result[:state]).to eq(:indeterminate)
      expect(result[:error_class]).to eq('JSON::ParserError')
    ensure
      probe[:writer]&.close unless probe[:writer]&.closed?
      probe[:reader]&.close unless probe[:reader]&.closed?
    end

    it 'returns :indeterminate for a JSON object with an unrecognised state value' do
      json = JSON.generate({ state: 'unexpected_value', actual_code: 200 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:state]).to eq(:indeterminate)
    end

    it 'returns :indeterminate for a JSON array (wrong top-level type)' do
      result = checker.send(:read_probe_result, probe_with_output('[]'))
      expect(result[:state]).to eq(:indeterminate)
    end

    it 'returns :free for well-formed JSON with state "free"' do
      json = JSON.generate({ state: 'free', actual_code: 204 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:state]).to eq(:free)
      expect(result[:actual_code]).to eq(204)
    end

    it 'returns :present for well-formed JSON with state "present"' do
      json = JSON.generate({ state: 'present', actual_code: 302 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:state]).to eq(:present)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: real subprocess path (no spawn_probe stub)
  # ---------------------------------------------------------------------------
  describe '#captive_portal_state with real helper subprocess', :loopback_socket do
    let(:checker) { described_class.new(verbose: false) }

    it 'returns :free via the real helper executable when the endpoint is portal-free' do
      with_local_http_server(response_code: 204) do |port|
        endpoint = { url: "http://127.0.0.1:#{port}/check", expected_code: 204 }
        allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
        expect(checker.captive_portal_state).to eq(:free)
      end
    end

    it 'returns :present via the real helper executable when the portal intercepts' do
      with_local_http_server(response_code: 302) do |port|
        endpoint = { url: "http://127.0.0.1:#{port}/check", expected_code: 204 }
        allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
        expect(checker.captive_portal_state).to eq(:present)
      end
    end

    it 'returns :indeterminate via the real helper executable on a network error' do
      closed_server = TCPServer.new('127.0.0.1', 0)
      closed_port = closed_server.addr[1]
      closed_server.close
      endpoint = { url: "http://127.0.0.1:#{closed_port}/check", expected_code: 204 }
      allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
      expect(checker.captive_portal_state).to eq(:indeterminate)
    end
  end

  def spawn_probe(endpoint:, payload: nil, raw_output: nil, delay: 0, post_write_delay: 0)
    reader, writer = IO.pipe
    child_code = <<~RUBY
      sleep(Float(ARGV[0]))
      payload = ARGV[1]
      post_write_delay = Float(ARGV[2])

      unless payload.empty?
        print(payload)
        $stdout.flush
      end

      sleep(post_write_delay) if post_write_delay.positive?
    RUBY

    output = raw_output || (payload ? JSON.generate(payload) : '')
    pid = Process.spawn(
      RbConfig.ruby,
      '-e',
      child_code,
      delay.to_s,
      output,
      post_write_delay.to_s,
      out: writer,
      err: File::NULL
    )
    writer.close
    spawned_pids << pid
    { pid: pid, reader: reader, endpoint: endpoint, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end
end
