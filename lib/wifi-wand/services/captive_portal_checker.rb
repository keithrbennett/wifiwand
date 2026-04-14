# frozen_string_literal: true

require 'json'
require 'net/http'
require 'rbconfig'
require 'timeout'
require 'yaml'
require_relative '../timing_constants'
require_relative '../connectivity_states'

module WifiWand
  class CaptivePortalChecker
    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Determines whether the current network connection is free of captive portal
    # interception by making real HTTP requests to well-known connectivity check
    # endpoints and verifying the response status codes.
    #
    # Multiple endpoints are checked concurrently so that a single misbehaving
    # endpoint cannot cause a false captive-portal detection without adding the
    # serial worst-case latency of back-to-back HTTP timeouts. Returns +:free+
    # if any endpoint returns the expected code, +:present+ only when at least
    # one endpoint returned a wrong status code and none succeeded, and
    # +:indeterminate+ when every endpoint failed with a network error.
    #
    # For full details on endpoint redundancy, return-value rationale, decision
    # flow, and terminology ("mismatch"), see docs/CONNECTIVITY_CHECKING.md
    # section "Captive Portal Detection".
    #
    # @return [Symbol] :free if no captive portal is detected,
    #   :present if a captive portal is confidently detected,
    #   :indeterminate if the result is indeterminate because all endpoints errored.
    # @see attempt_captive_portal_check for per-endpoint HTTP check details
    # @see captive_portal_check_endpoints for the configured endpoint list
    #
    def captive_portal_state
      endpoints = captive_portal_check_endpoints

      @output.puts "Testing captive portal via HTTP: #{endpoints.map { _1[:url] }.join(', ')}" if @verbose

      results = captive_portal_results(endpoints)

      state = if results.include?(ConnectivityStates::CAPTIVE_PORTAL_FREE)
        ConnectivityStates::CAPTIVE_PORTAL_FREE
      elsif results.include?(ConnectivityStates::CAPTIVE_PORTAL_PRESENT)
        ConnectivityStates::CAPTIVE_PORTAL_PRESENT
      else
        ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
      end

      if @verbose
        status = case state
                 when ConnectivityStates::CAPTIVE_PORTAL_FREE then 'free'
                 when ConnectivityStates::CAPTIVE_PORTAL_PRESENT then 'detected'
                 else 'indeterminate'
        end
        @output.puts "Captive portal results: #{results.inspect} — #{status}"
      end

      state
    end

    HELPER_RESULT_GRACE = 0.5

    private

    # We launch each speculative HTTP probe in its own Ruby subprocess because the
    # underlying stdlib HTTP calls are blocking and do not support reliable
    # cooperative cancellation in-process. A subprocess gives us a clearer and
    # safer cancellation boundary than Thread.kill, plain Ruby threads, or Async.
    def captive_portal_results(endpoints)
      probes = endpoints.filter_map { |endpoint| start_captive_portal_probe(endpoint) }
      results = []
      free_found = false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
        TimingConstants::HTTP_CONNECTIVITY_TIMEOUT + HELPER_RESULT_GRACE

      while probes.any?
        ready_readers = ready_probe_readers(probes, deadline)
        break if ready_readers.nil? || ready_readers.empty?

        ready_probes = probes.select { |probe| ready_readers.include?(probe[:reader]) }
        ready_probes.each do |probe|
          result = read_probe_result(probe)
          results << result[:state]
          log_probe_result(probe[:endpoint], result)
          finalize_probe(probe)
          probes.delete(probe)

          if result[:state] == ConnectivityStates::CAPTIVE_PORTAL_FREE
            free_found = true
            break
          end
        end

        break if free_found
      end

      results.concat(Array.new(probes.length, ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE))
      terminate_probes(probes)
      probes = []
      results
    ensure
      terminate_probes(probes || [])
    end

    def ready_probe_readers(probes, deadline)
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

    def start_captive_portal_probe(endpoint)
      reader, writer = IO.pipe
      pid = Process.spawn(*captive_portal_probe_command(endpoint), out: writer, err: File::NULL)
      writer.close
      { pid: pid, reader: reader, endpoint: endpoint }
    rescue => e
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      @output.puts "Failed to start captive portal helper for #{endpoint[:url]}: #{e.class}" if @verbose
      nil
    end

    def captive_portal_probe_command(endpoint)
      [
        RbConfig.ruby,
        captive_portal_probe_helper_path,
        endpoint[:url],
        endpoint[:expected_code].to_s,
        endpoint[:expected_body].to_s,
      ]
    end

    def captive_portal_probe_helper_path
      File.join(File.dirname(__FILE__), 'captive_portal_probe_helper.rb')
    end

    def read_probe_result(probe)
      payload = JSON.parse(probe[:reader].read.to_s.strip, symbolize_names: true)

      {
        state:       normalize_probe_state(payload[:state]),
        actual_code: payload[:actual_code],
        error_class: payload[:error_class],
      }
    rescue => e
      {
        state:       ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        error_class: e.class.to_s,
      }
    end

    def normalize_probe_state(state)
      case state
      when ConnectivityStates::CAPTIVE_PORTAL_FREE.to_s
        ConnectivityStates::CAPTIVE_PORTAL_FREE
      when ConnectivityStates::CAPTIVE_PORTAL_PRESENT.to_s
        ConnectivityStates::CAPTIVE_PORTAL_PRESENT
      else
        ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
      end
    end

    def log_probe_result(endpoint, result)
      return unless @verbose

      case result[:state]
      when ConnectivityStates::CAPTIVE_PORTAL_FREE, ConnectivityStates::CAPTIVE_PORTAL_PRESENT
        status = result[:state] == ConnectivityStates::CAPTIVE_PORTAL_FREE ? 'pass' : 'mismatch'
        @output.puts "Captive portal check #{endpoint[:url]}: " \
          "HTTP #{result[:actual_code]} (expected #{endpoint[:expected_code]}) -> #{status}"
      else
        @output.puts "Captive portal check network error for #{endpoint[:url]}: #{result[:error_class]}"
      end
    end

    def terminate_probes(probes)
      probes.each { |probe| terminate_probe(probe) }
    end

    def terminate_probe(probe)
      pid = probe[:pid]
      return unless pid

      Process.kill('TERM', pid)
      wait_for_probe_exit(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      finalize_probe(probe)
    end

    def finalize_probe(probe)
      probe[:reader]&.close unless probe[:reader]&.closed?
      reap_probe(probe[:pid])
      probe[:pid] = nil
    end

    def reap_probe(pid)
      return unless pid

      Process.wait(pid, Process::WNOHANG) || nil
    rescue Errno::ECHILD
      nil
    end

    def wait_for_probe_exit(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + HELPER_RESULT_GRACE

      loop do
        return if reap_probe(pid)
        return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(0.01)
      end

      Process.kill('KILL', pid)
      reap_probe(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    # Attempts an HTTP GET to a captive portal check endpoint and compares the response code.
    #
    # @param endpoint [Hash] with :url (String) and :expected_code (Integer)
    # @return [Symbol] :free if the server returned the expected HTTP status code
    # @return [Symbol] :present if the server returned a different status code
    # @return [Symbol] :indeterminate if a network error prevented any response
    #
    def perform_captive_portal_check(endpoint)
      uri = URI(endpoint[:url])
      expected_code = endpoint[:expected_code]
      expected_body = endpoint[:expected_body]

      Timeout.timeout(TimingConstants::HTTP_CONNECTIVITY_TIMEOUT) do
        response = Net::HTTP.get_response(uri)
        actual_code = response.code.to_i
        body_matches = expected_body.nil? || response.body.to_s.include?(expected_body)
        state = if actual_code == expected_code && body_matches
          ConnectivityStates::CAPTIVE_PORTAL_FREE
        else
          ConnectivityStates::CAPTIVE_PORTAL_PRESENT
        end
        { state: state, actual_code: actual_code }
      end
    rescue => e
      { state: ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE, error_class: e.class.to_s }
    end

    def attempt_captive_portal_check(endpoint) = perform_captive_portal_check(endpoint)[:state]

    # Loads captive portal check endpoint configuration from YAML.
    #
    # @return [Array<Hash>] Array of hashes with :url and :expected_code keys
    #
    def captive_portal_check_endpoints
      @captive_portal_check_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'captive_portal_check_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |e| e.transform_keys(&:to_sym) }
      end
    end
  end
end
