# frozen_string_literal: true

require 'net/http'
require 'timeout'
require 'yaml'
require 'async'
require 'async/barrier'
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

      results = []

      Async do |_task|
        barrier = Async::Barrier.new
        endpoints.each do |ep|
          barrier.async do
            case attempt_captive_portal_check(ep)
            when ConnectivityStates::CAPTIVE_PORTAL_FREE
              results << ConnectivityStates::CAPTIVE_PORTAL_FREE
              barrier.stop
            when ConnectivityStates::CAPTIVE_PORTAL_PRESENT
              results << ConnectivityStates::CAPTIVE_PORTAL_PRESENT
            else
              results << :error
            end
          end
        end
        barrier.wait
      rescue Async::Stop
        nil
      end.wait

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

    private

    # Attempts an HTTP GET to a captive portal check endpoint and compares the response code.
    #
    # @param endpoint [Hash] with :url (String) and :expected_code (Integer)
    # @return [Symbol] :free if the server returned the expected HTTP status code
    # @return [Symbol] :present if the server returned a different status code
    # @return [Symbol] :indeterminate if a network error prevented any response
    #
    def attempt_captive_portal_check(endpoint)
      uri = URI(endpoint[:url])
      expected_code = endpoint[:expected_code]

      Timeout.timeout(TimingConstants::HTTP_CONNECTIVITY_TIMEOUT) do
        response = Net::HTTP.get_response(uri)
        actual_code = response.code.to_i
        result = actual_code == expected_code

        if @verbose
          status = result ? 'pass' : 'mismatch'
          @output.puts "Captive portal check #{endpoint[:url]}: " \
            "HTTP #{actual_code} (expected #{expected_code}) -> #{status}"
        end

        result ? ConnectivityStates::CAPTIVE_PORTAL_FREE : ConnectivityStates::CAPTIVE_PORTAL_PRESENT
      end
    rescue => e
      @output.puts "Captive portal check network error for #{endpoint[:url]}: #{e.class}" if @verbose
      ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
    end

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
