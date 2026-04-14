# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'rbconfig'
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
        spawn_probe(endpoint: endpoints.last, delay: 5),
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(checker.captive_portal_state).to eq(:free)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 1
      expect { Process.kill(0, spawned_pids.last) }.to raise_error(Errno::ESRCH)
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
          spawn_probe(endpoint: endpoints.first, payload: { state: 'free', actual_code: 204 }),
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
            payload:  { state: 'present', actual_code: 302 },
          ),
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
        state: :free, actual_code: 204,
      )
    end

    it 'returns :present metadata when the endpoint returns a redirect' do
      mock_captive_portal_detected

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        state: :present, actual_code: 302,
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
        state: :free, actual_code: 200,
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
        state: :present, actual_code: 200,
      )
    end

    it 'returns :indeterminate metadata on network errors' do
      stub_short_connectivity_timeouts
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        state: :indeterminate, error_class: 'Errno::ECONNREFUSED',
      )
    end
  end

  def spawn_probe(endpoint:, payload: nil, delay: 0)
    reader, writer = IO.pipe
    child_code = <<~RUBY
      sleep(Float(ARGV[0]))
      if ARGV[1] && !ARGV[1].empty?
        print(ARGV[1])
        $stdout.flush
      end
    RUBY

    json_payload = payload ? JSON.generate(payload) : ''
    pid = Process.spawn(RbConfig.ruby, '-e', child_code, delay.to_s, json_payload, out: writer, err: File::NULL)
    writer.close
    spawned_pids << pid
    { pid: pid, reader: reader, endpoint: endpoint }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end
end
