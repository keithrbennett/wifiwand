# frozen_string_literal: true

require 'net/http'
require 'timeout'
require 'yaml'
require 'async'
require 'async/barrier'
require_relative '../timing_constants'

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
    # serial worst-case latency of back-to-back HTTP timeouts. Returns +true+
    # if any endpoint returns the expected code, +false+ only when at least one
    # endpoint returned a wrong status code and none succeeded, and +nil+ when
    # every endpoint failed with a network error so the result is indeterminate.
    #
    # For full details on endpoint redundancy, return-value rationale, decision
    # flow, and terminology ("mismatch"), see docs/CONNECTIVITY_CHECKING.md
    # section "Captive Portal Detection".
    #
    # @return [Boolean, nil] true if no captive portal is detected,
    #   false if a captive portal is confidently detected,
    #   nil if the result is indeterminate because all endpoints errored.
    # @see attempt_captive_portal_check for per-endpoint HTTP check details
    # @see captive_portal_check_endpoints for the configured endpoint list
    #
    def captive_portal_free?
      endpoints = captive_portal_check_endpoints

      @output.puts "Testing captive portal via HTTP: #{endpoints.map { _1[:url] }.join(', ')}" if @verbose

      results = []

      Async do |_task|
        barrier = Async::Barrier.new
        endpoints.each do |ep|
          barrier.async do
            case attempt_captive_portal_check(ep)
            when true
              results << :absent
              barrier.stop
            when false
              results << :present
            else
              results << :error
            end
          end
        end
        barrier.wait
      rescue Async::Stop
        nil
      end.wait

      free = if results.include?(:absent)
        true
      elsif results.include?(:present)
        false
      else
        nil
      end

      if @verbose
        status = case free
                 when true then 'free'
                 when false then 'detected'
                 else 'indeterminate'
        end
        @output.puts "Captive portal results: #{results.inspect} — #{status}"
      end

      free
    end

    private

    # Attempts an HTTP GET to a captive portal check endpoint and compares the response code.
    #
    # @param endpoint [Hash] with :url (String) and :expected_code (Integer)
    # @return [true]  if the server returned the expected HTTP status code
    # @return [false] if the server returned a different status code (portal redirect/page)
    # @return [nil]   if a network error prevented any response (caller should skip)
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

        result
      end
    rescue => e
      @output.puts "Captive portal check network error for #{endpoint[:url]}: #{e.class}" if @verbose
      nil
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
