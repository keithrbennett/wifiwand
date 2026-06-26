# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'rbconfig'
require 'socket'
require 'stringio'
require_relative '../../../lib/wifi_wand/services/captive_portal_checker'

describe WifiWand::CaptivePortalChecker do
  include TestHelpers

  describe '#captive_portal_login_required' do
    let(:checker) { described_class.new(verbose: false) }
    let(:open_probe_writers) { [] }
    let(:endpoints) do
      [
        { url: 'http://first.example.com/check', expected_code: 204 },
        { url: 'http://second.example.com/check', expected_code: 204 },
      ]
    end

    after do
      open_probe_writers.each do |writer|
        writer.close unless writer.closed?
      end
    end

    before do
      allow(checker).to receive(:captive_portal_check_endpoints).and_return(endpoints)
    end

    it 'returns :no when any helper reports a successful endpoint' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[yes no])

      expect(checker.captive_portal_login_required).to eq(:no)
    end

    it 'returns :yes when endpoints mismatch and none succeed' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[yes unknown])

      expect(checker.captive_portal_login_required).to eq(:yes)
    end

    it 'returns :unknown when every endpoint errors' do
      allow(checker).to receive(:captive_portal_results).and_return(%i[unknown unknown])

      expect(checker.captive_portal_login_required).to eq(:unknown)
    end

    it 'returns promptly after a helper reports :no and terminates slower helpers' do
      pending_probe = open_probe(endpoint: endpoints.last).merge(pid: 12_345)
      terminated_probes = []
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        completed_probe(endpoint: endpoints.first, payload: { login_required: 'no', actual_code: 204 }),
        pending_probe
      )
      allow(checker).to receive(:terminate_probe) do |probe, grace:|
        terminated_probes << [probe, grace]
        probe[:reader]&.close unless probe[:reader]&.closed?
        probe[:pid] = nil
      end

      result = nil
      Timeout.timeout(1) { result = checker.captive_portal_login_required }

      expect(result).to eq(:no)
      expect(terminated_probes).to include([pending_probe, checker.helper_result_grace])
      expect(pending_probe[:reader]).to be_closed
      expect(pending_probe[:pid]).to be_nil
    end

    it 'returns promptly when a helper writes partial JSON and then stalls' do
      stub_const('WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT', 0.1)
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        open_probe(endpoint: endpoints.first, raw_output: '{"login_required":"no"')
      )

      result = nil
      Timeout.timeout(1) { result = checker.captive_portal_login_required }

      expect(result).to eq(:unknown)
    end

    it 'returns parsed login_required before a successful helper closes stdout' do
      allow(checker).to receive_messages(
        captive_portal_check_endpoints: [endpoints.first],
        start_captive_portal_probe:     open_probe(
          endpoint: endpoints.first,
          payload:  { login_required: 'no', actual_code: 204 }
        )
      )

      result = nil
      Timeout.timeout(2) { result = checker.captive_portal_login_required }

      expect(result).to eq(:no)
    end

    it 'uses zero helper grace when the caller provides a timeout budget' do
      allow(checker).to receive_messages(
        start_captive_portal_probe: open_probe(endpoint: endpoints.first),
        ready_probe_readers:        []
      )
      observed_graces = []
      allow(checker).to receive(:terminate_probes).and_wrap_original do |original, probes, grace:|
        observed_graces << grace
        original.call(probes, grace: grace)
      end

      result = nil
      Timeout.timeout(1) { result = checker.captive_portal_login_required(timeout_in_secs: 0.05) }

      expect(result).to eq(:unknown)
      expect(observed_graces).to include(0)
    end

    it 'uses zero successful-finalization grace when the caller provides a timeout budget' do
      allow(checker).to receive_messages(
        captive_portal_check_endpoints: [endpoints.first],
        start_captive_portal_probe:     completed_probe(
          endpoint: endpoints.first,
          payload:  { login_required: 'no', actual_code: 204 }
        )
      )
      observed_graces = []
      allow(checker).to receive(:finalize_probe).and_wrap_original do |original, probe, grace:|
        observed_graces << grace
        original.call(probe, grace: grace)
      end

      result = nil
      Timeout.timeout(1) { result = checker.captive_portal_login_required(timeout_in_secs: 0.2) }

      expect(result).to eq(:no)
      expect(observed_graces).to include(0)
    end

    context 'with verbose mode' do
      let(:err_output) { StringIO.new }
      let(:checker) do
        described_class.new(runtime_config: WifiWand::RuntimeConfig.new(verbose: true,
          err_stream: err_output))
      end

      before do
        allow(checker).to receive(:captive_portal_check_endpoints).and_return(endpoints)
      end

      it 'logs the endpoints being checked' do
        allow(checker).to receive(:captive_portal_results).and_return([:no])

        checker.captive_portal_login_required
        expect(err_output.string).to include('Testing captive portal via HTTP:')
      end

      it 'logs a pass result' do
        allow(checker).to receive(:start_captive_portal_probe).and_return(
          completed_probe(endpoint: endpoints.first, payload: { login_required: 'no', actual_code: 204 })
        )

        checker.captive_portal_login_required
        expect(err_output.string).to include('pass')
      end
    end

    context 'with verbose mode and captive portal login required' do
      let(:err_output) { StringIO.new }
      let(:checker) do
        described_class.new(runtime_config: WifiWand::RuntimeConfig.new(verbose: true,
          err_stream: err_output))
      end

      before do
        allow(checker).to receive_messages(
          captive_portal_check_endpoints: [endpoints.first],
          start_captive_portal_probe:     completed_probe(
            endpoint: endpoints.first,
            payload:  { login_required: 'yes', actual_code: 302 }
          )
        )
      end

      it 'logs results array and required status' do
        checker.captive_portal_login_required
        expect(err_output.string).to include('mismatch')
        expect(err_output.string).to include('required')
      end
    end
  end

  describe '#start_captive_portal_probe' do
    let(:checker) { described_class.new(verbose: false) }
    let(:endpoint) { { url: 'http://example.com/check', expected_code: 204 } }

    it 'starts a helper process and returns the reader metadata' do
      reader, writer = IO.pipe
      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_return(12_345)

      probe = checker.send(:start_captive_portal_probe, endpoint)

      expect(Process).to have_received(:spawn).with(
        RbConfig.ruby,
        end_with('captive_portal_probe_helper.rb'),
        endpoint[:url],
        '204',
        '',
        out: writer,
        err: File::NULL
      )
      expect(probe).to include(pid: 12_345, reader: reader, endpoint: endpoint, buffer: +'')
      expect(probe[:eof]).to be(false)
      expect(writer).to be_closed
    ensure
      reader&.close unless reader&.closed?
    end

    it 'returns nil and closes the helper pipe when spawn fails' do
      reader, writer = IO.pipe
      allow(IO).to receive(:pipe).and_return([reader, writer])
      allow(Process).to receive(:spawn).and_raise(Errno::EAGAIN)

      expect(checker.send(:start_captive_portal_probe, endpoint)).to be_nil
      expect(reader).to be_closed
      expect(writer).to be_closed
    end
  end

  describe '#probe_endpoint' do
    let(:checker) { described_class.new(verbose: false) }
    let(:endpoint) { { url: 'http://example.com/check', expected_code: 204 } }

    it 'returns the endpoint probe metadata used by subprocess helpers' do
      allow(checker).to receive(:perform_captive_portal_check).and_return(
        login_required: :unknown,
        error_class:    'SocketError'
      )

      expect(checker.probe_endpoint(endpoint)).to eq(
        login_required: :unknown,
        error_class:    'SocketError'
      )
    end
  end

  describe '#perform_captive_portal_check' do
    let(:checker) { described_class.new(verbose: false) }
    let(:endpoint) { { url: 'http://example.com/check', expected_code: 204 } }

    it 'returns :no metadata when the endpoint returns the expected code' do
      stub_captive_portal_response(checker, code: '204')

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        login_required: :no, actual_code: 204
      )
    end

    it 'returns :yes metadata when the endpoint returns a redirect' do
      stub_captive_portal_response(checker, code: '302')

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        login_required: :yes, actual_code: 302
      )
    end

    it 'returns :no when both code and expected body match' do
      endpoint_with_body = {
        url:           'http://example.com/connecttest.txt',
        expected_code: 200,
        expected_body: 'Microsoft Connect Test',
      }
      stub_captive_portal_response(checker, code: '200', body: 'Microsoft Connect Test')

      expect(checker.send(:perform_captive_portal_check, endpoint_with_body)).to eq(
        login_required: :no, actual_code: 200
      )
    end

    it 'returns :yes when the code matches but the body does not' do
      endpoint_with_body = {
        url:           'http://example.com/connecttest.txt',
        expected_code: 200,
        expected_body: 'Microsoft Connect Test',
      }
      stub_captive_portal_response(checker, code: '200', body: '<html>Login</html>')

      expect(checker.send(:perform_captive_portal_check, endpoint_with_body)).to eq(
        login_required: :yes, actual_code: 200
      )
    end

    it 'returns :unknown metadata on network errors' do
      stub_short_connectivity_timeouts
      allow(checker).to receive(:captive_portal_http_response).and_raise(Errno::ECONNREFUSED)

      expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
        login_required: :unknown, error_class: 'Errno::ECONNREFUSED'
      )
    end

    it 'returns :unknown metadata on HTTP-level network failures' do
      allow(checker).to receive(:captive_portal_http_response).and_raise(SocketError)

      expect do
        expect(checker.send(:perform_captive_portal_check, endpoint)).to eq(
          login_required: WifiWand::ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN,
          error_class:    'SocketError'
        )
      end.not_to raise_error
    end

    it 'uses direct HTTP without proxy environment settings' do
      uri = URI('http://example.com/check')
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPResponse)
      allow(http).to receive(:get).with('/check').and_return(response)

      expect(Net::HTTP).to receive(:start).with(
        'example.com',
        80,
        nil,
        use_ssl:      false,
        open_timeout: WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT,
        read_timeout: WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT
      ).and_yield(http)

      expect(checker.send(:captive_portal_http_response, uri)).to eq(response)
    end

    it 'uses direct HTTPS with SSL enabled' do
      uri = URI('https://example.com/check')
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPResponse)
      allow(http).to receive(:get).with('/check').and_return(response)

      expect(Net::HTTP).to receive(:start).with(
        'example.com',
        443,
        nil,
        use_ssl:      true,
        open_timeout: WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT,
        read_timeout: WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT
      ).and_yield(http)

      expect(checker.send(:captive_portal_http_response, uri)).to eq(response)
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

    it 'returns :unknown and records the error class for empty output' do
      result = checker.send(:read_probe_result, probe_with_output(''))
      expect(result[:login_required]).to eq(:unknown)
      expect(result[:error_class]).to be_a(String)
    end

    it 'returns :unknown and records the error class for malformed JSON' do
      result = checker.send(:read_probe_result, probe_with_output('not json {{{'))
      expect(result[:login_required]).to eq(:unknown)
      expect(result[:error_class]).to be_a(String)
    end

    it 'returns nil for partial JSON before EOF and fails only after EOF' do
      probe = probe_with_output('{"login_required":"no"', close_writer: false)

      expect(checker.send(:read_probe_result, probe)).to be_nil

      probe[:writer].close
      result = checker.send(:read_probe_result, probe)
      expect(result[:login_required]).to eq(:unknown)
      expect(result[:error_class]).to eq('JSON::ParserError')
    ensure
      probe[:writer]&.close unless probe[:writer]&.closed?
      probe[:reader]&.close unless probe[:reader]&.closed?
    end

    it 'returns :unknown for a JSON object with an unrecognised login_required value' do
      json = JSON.generate({ login_required: 'unexpected_value', actual_code: 200 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:login_required]).to eq(:unknown)
    end

    it 'returns :unknown for a JSON array (wrong top-level type)' do
      result = checker.send(:read_probe_result, probe_with_output('[]'))
      expect(result[:login_required]).to eq(:unknown)
    end

    it 'returns :no for well-formed JSON with login_required "no"' do
      json = JSON.generate({ login_required: 'no', actual_code: 204 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:login_required]).to eq(:no)
      expect(result[:actual_code]).to eq(204)
    end

    it 'returns :yes for well-formed JSON with login_required "yes"' do
      json = JSON.generate({ login_required: 'yes', actual_code: 302 })
      result = checker.send(:read_probe_result, probe_with_output(json))
      expect(result[:login_required]).to eq(:yes)
    end
  end

  describe '#captive_portal_check_endpoints' do
    let(:checker) { described_class.new(verbose: false) }

    it 'loads endpoint configuration from the packaged YAML file with symbol keys' do
      endpoints = checker.send(:captive_portal_check_endpoints)

      expect(endpoints).not_to be_empty
      expect(endpoints).to all(include(:url, :expected_code))
      expect(endpoints).to all(satisfy { |endpoint| endpoint.keys.none?(String) })
    end
  end

  describe 'verbose result logging' do
    let(:err_output) { StringIO.new }
    let(:checker) do
      described_class.new(runtime_config: WifiWand::RuntimeConfig.new(verbose: true, err_stream: err_output))
    end
    let(:endpoint) { { url: 'http://example.com/check', expected_code: 204 } }

    before do
      allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
    end

    it 'logs unknown aggregate status when no helper reaches a decision' do
      allow(checker).to receive(:captive_portal_results).and_return([:unknown])

      expect(checker.captive_portal_login_required).to eq(:unknown)
      expect(err_output.string).to include('unknown')
    end

    it 'logs helper network errors without treating them as captive portals' do
      allow(checker).to receive(:start_captive_portal_probe).and_return(
        completed_probe(
          endpoint: endpoint,
          payload:  { login_required: 'unknown', error_class: 'SocketError' }
        )
      )

      expect(checker.captive_portal_login_required).to eq(:unknown)
      expect(err_output.string).to include(
        'Captive portal check network error for http://example.com/check: SocketError'
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: real subprocess path (no spawn_probe stub)
  # ---------------------------------------------------------------------------
  describe '#captive_portal_login_required with real helper subprocess', :loopback_socket do
    let(:checker) { described_class.new(verbose: false) }

    it 'returns :no via the real helper executable when the endpoint is no-login-required' do
      with_local_http_server(response_code: 204) do |port|
        endpoint = { url: "http://127.0.0.1:#{port}/check", expected_code: 204 }
        allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
        expect(checker.captive_portal_login_required(timeout_in_secs: external_process_timeout)).to eq(:no)
      end
    end

    it 'returns :yes via the real helper executable when the portal intercepts' do
      with_local_http_server(response_code: 302) do |port|
        endpoint = { url: "http://127.0.0.1:#{port}/check", expected_code: 204 }
        allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
        expect(checker.captive_portal_login_required(timeout_in_secs: external_process_timeout)).to eq(:yes)
      end
    end

    it 'returns :unknown via the real helper executable on a network error' do
      closed_server = TCPServer.new('127.0.0.1', 0)
      closed_port = closed_server.addr[1]
      closed_server.close
      endpoint = { url: "http://127.0.0.1:#{closed_port}/check", expected_code: 204 }
      allow(checker).to receive(:captive_portal_check_endpoints).and_return([endpoint])
      expect(checker.captive_portal_login_required(timeout_in_secs: external_process_timeout)).to eq(:unknown)
    end
  end

  def open_probe(endpoint:, payload: nil, raw_output: nil)
    reader, writer = IO.pipe
    output = raw_output || (payload ? JSON.generate(payload) : '')
    writer.write(output) unless output.empty?
    writer.flush
    open_probe_writers << writer
    { pid: nil, reader: reader, endpoint: endpoint, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def completed_probe(endpoint:, payload:)
    reader, writer = IO.pipe
    writer.write(JSON.generate(payload))
    writer.close
    { pid: nil, reader: reader, endpoint: endpoint, buffer: +'', eof: false }
  rescue
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    raise
  end

  def stub_captive_portal_response(checker, code:, body: '')
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(checker).to receive(:captive_portal_http_response).and_return(response)
  end
end
