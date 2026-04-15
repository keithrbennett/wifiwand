# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'socket'
require_relative '../../../lib/wifi-wand/services/captive_portal_probe_helper'

describe WifiWand::CaptivePortalProbeHelper do
  include TestHelpers

  # Build a plain double whose perform_captive_portal_check returns +result+.
  # A plain double (not instance_double) is used because the method is private
  # and we invoke it via +send+ inside CaptivePortalProbeHelper.run.
  def stub_checker(result)
    dbl = double('CaptivePortalChecker')
    allow(dbl).to receive(:perform_captive_portal_check).and_return(result)
    dbl
  end

  # ---------------------------------------------------------------------------
  # parse_argv
  # ---------------------------------------------------------------------------
  describe '.parse_argv' do
    it 'returns a valid endpoint hash without body when only url and code are given' do
      result = described_class.parse_argv(['http://example.com/check', '204'])
      expect(result).to eq(url: 'http://example.com/check', expected_code: 204, expected_body: nil)
    end

    it 'returns a valid endpoint hash with body when a body arg is provided' do
      result = described_class.parse_argv(['http://example.com/check', '200', 'Success'])
      expect(result).to eq(url: 'http://example.com/check', expected_code: 200, expected_body: 'Success')
    end

    it 'treats an empty-string body arg as nil' do
      result = described_class.parse_argv(['http://example.com/check', '204', ''])
      expect(result[:expected_body]).to be_nil
    end

    it 'raises ArgumentError when argv is empty' do
      expect { described_class.parse_argv([]) }.to raise_error(ArgumentError, /url/)
    end

    it 'raises ArgumentError when expected_code is missing' do
      expect { described_class.parse_argv(['http://example.com']) }
        .to raise_error(ArgumentError, /expected_code/)
    end

    it 'raises ArgumentError when expected_code is not a valid integer string' do
      expect { described_class.parse_argv(['http://example.com', 'two-hundred']) }
        .to raise_error(ArgumentError)
    end
  end

  # ---------------------------------------------------------------------------
  # run — hermetic unit tests using an injected checker double
  # ---------------------------------------------------------------------------
  describe '.run' do
    let(:output) { StringIO.new }

    it 'outputs JSON with state "free" when the probe reports portal-free' do
      checker = stub_checker({ state: :free, actual_code: 204 })
      described_class.run(['http://example.com/check', '204'], output: output, checker: checker)

      result = JSON.parse(output.string, symbolize_names: true)
      expect(result[:state]).to eq('free')
      expect(result[:actual_code]).to eq(204)
    end

    it 'outputs JSON with state "present" when a captive portal is detected' do
      checker = stub_checker({ state: :present, actual_code: 302 })
      described_class.run(['http://example.com/check', '204'], output: output, checker: checker)

      result = JSON.parse(output.string, symbolize_names: true)
      expect(result[:state]).to eq('present')
      expect(result[:actual_code]).to eq(302)
    end

    it 'outputs JSON with state "indeterminate" and error_class on a network error' do
      checker = stub_checker({ state: :indeterminate, error_class: 'Errno::ECONNREFUSED' })
      described_class.run(['http://example.com/check', '204'], output: output, checker: checker)

      result = JSON.parse(output.string, symbolize_names: true)
      expect(result[:state]).to eq('indeterminate')
      expect(result[:error_class]).to eq('Errno::ECONNREFUSED')
    end

    it 'outputs indeterminate JSON when argv is empty (missing url)' do
      described_class.run([], output: output)

      result = JSON.parse(output.string, symbolize_names: true)
      expect(result[:state]).to eq('indeterminate')
      expect(result[:error_class]).to be_a(String)
      expect(result[:error_message]).to be_a(String)
    end

    it 'outputs indeterminate JSON when expected_code is non-numeric' do
      described_class.run(['http://example.com/check', 'not-a-number'], output: output)

      result = JSON.parse(output.string, symbolize_names: true)
      expect(result[:state]).to eq('indeterminate')
      expect(result[:error_class]).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # Subprocess integration: exercise the real script entry-point
  # Tests here run the helper script as an actual child process so the CLI
  # contract (ARGV parsing → JSON stdout) is verified end-to-end.
  # ---------------------------------------------------------------------------
  describe 'real script entry-point (subprocess)' do
    let(:helper_script) do
      File.expand_path('../../../lib/wifi-wand/services/captive_portal_probe_helper.rb', __dir__)
    end

    # Spawns the helper as a child process, captures its stdout, then ensures the
    # process is reaped regardless of outcome.  Returns the raw output string.
    def run_helper(*args, timeout: 5)
      pid = nil
      reader, writer = IO.pipe
      pid = Process.spawn(RbConfig.ruby, helper_script, *args.map(&:to_s), out: writer, err: File::NULL)
      writer.close

      reader.wait_readable(timeout) ? reader.read : ''
    ensure
      begin
        reader.close
      rescue IOError
        nil
      end
      if pid
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        end
      end
    end

    it 'outputs valid indeterminate JSON when called with no arguments' do
      raw = run_helper
      result = JSON.parse(raw, symbolize_names: true)
      expect(result[:state]).to eq('indeterminate')
      expect(result[:error_class]).to be_a(String)
    end

    it 'outputs valid indeterminate JSON when expected_code is not an integer' do
      raw = run_helper('http://example.com/check', 'bad')
      result = JSON.parse(raw, symbolize_names: true)
      expect(result[:state]).to eq('indeterminate')
    end

    # The following tests open a loopback TCP server and are skipped in
    # sandboxed environments where socket binding is not permitted.
    context 'with a real loopback HTTP server', :loopback_socket do
      it 'outputs JSON with state "free" when the endpoint responds with the expected code' do
        with_local_http_server(response_code: 204) do |port|
          raw = run_helper("http://127.0.0.1:#{port}/check", '204')
          result = JSON.parse(raw, symbolize_names: true)
          expect(result[:state]).to eq('free')
          expect(result[:actual_code]).to eq(204)
        end
      end

      it 'outputs JSON with state "present" when the portal intercepts the request' do
        with_local_http_server(response_code: 302) do |port|
          raw = run_helper("http://127.0.0.1:#{port}/check", '204')
          result = JSON.parse(raw, symbolize_names: true)
          expect(result[:state]).to eq('present')
          expect(result[:actual_code]).to eq(302)
        end
      end

      it 'outputs JSON with state "indeterminate" when the endpoint is unreachable' do
        # Grab a free port then close the server so connections are refused.
        closed_server = TCPServer.new('127.0.0.1', 0)
        closed_port   = closed_server.addr[1]
        closed_server.close

        raw = run_helper("http://127.0.0.1:#{closed_port}/check", '204')
        result = JSON.parse(raw, symbolize_names: true)
        expect(result[:state]).to eq('indeterminate')
        expect(result[:error_class]).to be_a(String)
      end

      it 'outputs state "free" when both HTTP code and body match the expected values' do
        with_local_http_server(response_code: 200, response_body: 'Microsoft Connect Test') do |port|
          raw = run_helper("http://127.0.0.1:#{port}/check", '200', 'Microsoft Connect Test')
          result = JSON.parse(raw, symbolize_names: true)
          expect(result[:state]).to eq('free')
          expect(result[:actual_code]).to eq(200)
        end
      end

      it 'outputs state "present" when the HTTP code matches but the body does not' do
        with_local_http_server(response_code: 200, response_body: '<html>Login</html>') do |port|
          raw = run_helper("http://127.0.0.1:#{port}/check", '200', 'Microsoft Connect Test')
          result = JSON.parse(raw, symbolize_names: true)
          expect(result[:state]).to eq('present')
        end
      end

      it 'omits expected_body check when the third argument is empty' do
        with_local_http_server(response_code: 204) do |port|
          # Passing an empty third argument should behave the same as no body constraint.
          raw = run_helper("http://127.0.0.1:#{port}/check", '204', '')
          result = JSON.parse(raw, symbolize_names: true)
          expect(result[:state]).to eq('free')
        end
      end
    end
  end
end
