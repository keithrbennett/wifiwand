# frozen_string_literal: true

require 'json'
require 'net/http'
require 'rbconfig'
require 'timeout'
require 'yaml'
require_relative '../timing_constants'
require_relative '../connectivity_states'
require_relative '../runtime_config'
require_relative 'process_probe_manager'

module WifiWand
  class CaptivePortalChecker
    include ProcessProbeManager

    private attr_reader :runtime_config, :http_connectivity_timeout_in_secs

    def initialize(verbose: false, output: $stdout, runtime_config: nil,
      http_connectivity_timeout_in_secs: TimingConstants::HTTP_CONNECTIVITY_TIMEOUT)
      @runtime_config = runtime_config || RuntimeConfig.new(
        verbose:    verbose,
        out_stream: output
      )
      @http_connectivity_timeout_in_secs = http_connectivity_timeout_in_secs
    end

    # Determines whether captive portal login appears to be required now by
    # making real HTTP requests to well-known connectivity check endpoints and
    # verifying the response status codes.
    #
    # Multiple endpoints are checked concurrently so that a single misbehaving
    # endpoint cannot cause a false captive-portal detection without adding the
    # serial worst-case latency of back-to-back HTTP timeouts. Returns +:no+
    # if any endpoint returns the expected response, +:yes+ only when at least
    # one endpoint returned an unexpected response and none succeeded, and
    # +:unknown+ when every endpoint failed with a network error.
    #
    # For full details on endpoint redundancy, return-value rationale, decision
    # flow, and terminology ("mismatch"), see docs/CONNECTIVITY_CHECKING.md
    # section "Captive Portal Detection".
    #
    # @return [Symbol] :no if login does not appear to be required,
    #   :yes if login appears to be required,
    #   :unknown if the requirement could not be determined because all endpoints errored.
    # @see perform_captive_portal_check for per-endpoint HTTP check details
    # @see captive_portal_check_endpoints for the configured endpoint list
    #
    def captive_portal_login_required(timeout_in_secs: nil)
      endpoints = captive_portal_check_endpoints

      err_output.puts "Testing captive portal via HTTP: #{endpoints.map { _1[:url] }.join(', ')}" if verbose?

      results = captive_portal_results(endpoints, timeout_in_secs: timeout_in_secs)

      login_required = if results.include?(ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED)
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
      elsif results.include?(ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED)
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED
      else
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN
      end

      if verbose?
        status = case login_required
                 when ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED then 'not required'
                 when ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED then 'required'
                 else 'unknown'
        end
        err_output.puts "Captive portal results: #{results.inspect} — #{status}"
      end

      login_required
    end

    # Shared probe interface used by the helper subprocess wrapper.
    #
    # @param endpoint [Hash] captive-portal endpoint configuration
    # @return [Hash] probe metadata including :login_required and either :actual_code or :error_class
    def probe_endpoint(endpoint)
      perform_captive_portal_check(endpoint)
    end

    # Seconds given to a probe subprocess after SIGTERM before escalating to SIGKILL.
    # Short enough to keep overall check latency low, long enough for a clean exit.
    HELPER_RESULT_GRACE = 0.5

    private def captive_portal_results(endpoints, timeout_in_secs: nil)
      probes = endpoints.filter_map { |endpoint| start_captive_portal_probe(endpoint) }
      results = []
      no_login_required_found = false
      probe_timeout = timeout_in_secs || http_connectivity_timeout_in_secs
      terminate_grace = timeout_in_secs ? 0 : helper_result_grace
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + probe_timeout

      while probes.any?
        ready_readers = ready_probe_readers(probes, deadline)
        break if ready_readers.nil? || ready_readers.empty?

        ready_probes = probes.select { |probe| ready_readers.include?(probe[:reader]) }
        ready_probes.each do |probe|
          result = read_probe_result(probe)
          next if result.nil?

          results << result[:login_required]
          log_probe_result(probe[:endpoint], result)
          finalize_probe(probe, grace: terminate_grace)
          probes.delete(probe)

          if result[:login_required] == ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
            no_login_required_found = true
            break
          end
        end

        break if no_login_required_found
      end

      # Probes still in-flight when we exited the loop (deadline hit or a no-login result arrived)
      # never wrote a result. Count each as :unknown before terminating them.
      results.concat(Array.new(probes.length, ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN))
      terminate_probes(probes, grace: terminate_grace)
      probes = []
      results
    ensure
      terminate_probes(probes || [], grace: terminate_grace || helper_result_grace)
    end

    private def ready_probe_readers(probes, deadline)
      timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return [] if timeout <= 0

      ready_readers, _writables, _errorables = IO.select(
        probes.map { |probe| probe[:reader] },
        nil,
        nil,
        timeout
      )
      ready_readers
    end

    private def start_captive_portal_probe(endpoint)
      reader, writer = IO.pipe
      pid = Process.spawn(*captive_portal_probe_command(endpoint), out: writer, err: File::NULL)
      writer.close
      { pid: pid, reader: reader, endpoint: endpoint, buffer: +'', eof: false }
    rescue SystemCallError, IOError => e
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      err_output.puts "Failed to start captive portal helper for #{endpoint[:url]}: #{e.class}" if verbose?
      nil
    end

    private def captive_portal_probe_command(endpoint)
      [
        RbConfig.ruby,
        captive_portal_probe_helper_path,
        endpoint[:url],
        endpoint[:expected_code].to_s,
        endpoint[:expected_body].to_s,
      ]
    end

    private def captive_portal_probe_helper_path
      File.join(File.dirname(__FILE__), 'captive_portal_probe_helper.rb')
    end

    private def read_probe_result(probe)
      drain_probe_reader(probe)
      payload_text = probe[:buffer].strip

      return failure_probe_result(EOFError) if probe[:eof] && payload_text.empty?

      payload = JSON.parse(payload_text, symbolize_names: true)
      return failure_probe_result(TypeError) unless payload.is_a?(Hash)

      {
        login_required: normalize_probe_login_required(payload[:login_required]),
        actual_code:    payload[:actual_code],
        error_class:    payload[:error_class],
      }
    rescue JSON::ParserError
      return nil unless probe[:eof]

      failure_probe_result(JSON::ParserError)
    rescue SystemCallError, IOError => e
      failure_probe_result(e.class)
    end

    private def drain_probe_reader(probe)
      loop do
        chunk = probe[:reader].read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable
          return
        when nil
          probe[:eof] = true
          return
        else
          probe[:buffer] << chunk
        end
      end
    end

    private def failure_probe_result(error_class)
      {
        login_required: ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN,
        error_class:    error_class.to_s,
      }
    end

    private def normalize_probe_login_required(login_required)
      case login_required
      when ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED.to_s
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
      when ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED.to_s
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED
      else
        ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN
      end
    end

    private def log_probe_result(endpoint, result)
      return unless verbose?

      case result[:login_required]
      when ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED, ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED
        status =
          if result[:login_required] == ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
            'pass'
          else
            'mismatch'
          end
        err_output.puts "Captive portal check #{endpoint[:url]}: " \
          "HTTP #{result[:actual_code]} (expected #{endpoint[:expected_code]}) -> #{status}"
      else
        err_output.puts "Captive portal check network error for #{endpoint[:url]}: #{result[:error_class]}"
      end
    end

    private def verbose? = runtime_config.verbose

    private def output = runtime_config.out_stream

    private def err_output = runtime_config.err_stream

    # Attempts an HTTP GET to a captive portal check endpoint and compares the response.
    #
    # @param endpoint [Hash] with :url (String), :expected_code (Integer), and optional :expected_body
    # @return [Hash] :login_required (:no, :yes, or :unknown) and :actual_code on success
    # @return [Hash] :login_required (:unknown) and :error_class on network failure
    #
    private def perform_captive_portal_check(endpoint)
      uri = URI(endpoint[:url])
      expected_code = endpoint[:expected_code]
      expected_body = endpoint[:expected_body]

      Timeout.timeout(http_connectivity_timeout_in_secs) do
        response = captive_portal_http_response(uri)
        actual_code = response.code.to_i
        body_matches = expected_body.nil? || response.body.to_s.include?(expected_body)
        login_required = if actual_code == expected_code && body_matches
          ConnectivityStates::CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
        else
          ConnectivityStates::CAPTIVE_PORTAL_LOGIN_REQUIRED
        end
        { login_required: login_required, actual_code: actual_code }
      end
    rescue URI::InvalidURIError, Timeout::Error, SocketError, SystemCallError, IOError,
      Net::HTTPError => e
      { login_required: ConnectivityStates::CAPTIVE_PORTAL_LOGIN_UNKNOWN, error_class: e.class.to_s }
    end

    private def captive_portal_http_response(uri)
      Net::HTTP.start(
        uri.hostname,
        uri.port,
        nil,
        use_ssl:      uri.scheme == 'https',
        open_timeout: http_connectivity_timeout_in_secs,
        read_timeout: http_connectivity_timeout_in_secs
      ) do |http|
        http.get(uri.request_uri)
      end
    end

    # Loads captive portal check endpoint configuration from YAML.
    #
    # @return [Array<Hash>] Array of hashes with :url and :expected_code keys
    #
    private def captive_portal_check_endpoints
      @captive_portal_check_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'captive_portal_check_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |e| e.transform_keys(&:to_sym) }
      end
    end
  end
end
