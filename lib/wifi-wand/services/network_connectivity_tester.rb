# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'yaml'
require 'ipaddr'
require 'async'
require 'async/barrier'
require_relative '../timing_constants'

module WifiWand
  class NetworkConnectivityTester
    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
    end

    # Tests both TCP connectivity to internet hosts and DNS resolution.
    # If tcp_working or dns_working parameters are provided, uses them instead of querying the system.
    def connected_to_internet?(tcp_working = nil, dns_working = nil)
      tcp = tcp_working.nil? ? tcp_connectivity? : tcp_working
      dns = dns_working.nil? ? dns_working? : dns_working
      tcp && dns
    end

    # Fast connectivity check optimized for continuous monitoring (e.g., log command).
    #
    # This method provides a quick internet connectivity test that:
    # - Uses only 3 geographically diverse TCP endpoints
    # - Has a short 1-second timeout per endpoint
    # - Returns immediately when first endpoint responds (~50-200ms typically)
    # - Works globally including China (uses Baidu endpoint)
    # - Skips DNS testing (often cached, less useful for real-time monitoring)
    #
    # Endpoints tested:
    # - 1.1.1.1:443 (Cloudflare) - Fast globally except China
    # - 8.8.8.8:443 (Google) - Fast globally except China
    # - 180.76.76.76:443 (Baidu) - Fast in China, accessible globally
    #
    # @return [Boolean] true if any endpoint is reachable, false otherwise
    #
    # Performance:
    # - Best case: ~50-200ms (when any endpoint responds quickly)
    # - Worst case: ~1 second (when all endpoints timeout)
    #
    # This is ideal for the log command where speed matters more than thoroughness.
    # Use connected_to_internet? for comprehensive checks in status/info commands.
    #
    def fast_connectivity?
      fast_endpoints = [
        { host: '1.1.1.1', port: 443 },     # Cloudflare
        { host: '8.8.8.8', port: 443 },     # Google
        { host: '180.76.76.76', port: 443 } # Baidu (China-friendly)
      ]

      if @verbose
        endpoints_list = fast_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Fast connectivity check to: #{endpoints_list}"
      end

      run_parallel_checks(fast_endpoints, TimingConstants::FAST_CONNECTIVITY_TIMEOUT) do |endpoint|
        attempt_fast_tcp_connection(endpoint)
      end
    end

    # Tests TCP connectivity to internet hosts (not localhost)
    def tcp_connectivity?
      test_endpoints = tcp_test_endpoints

      if @verbose
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Testing internet TCP connectivity to: #{endpoints_list}"
      end

      run_parallel_checks(test_endpoints,
        TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT) do |endpoint|
        attempt_tcp_connection(endpoint)
      end
    end

    # Tests DNS resolution capability
    def dns_working?
      test_domains = dns_test_domains

      if @verbose
        @output.puts "Testing DNS resolution for domains: #{test_domains.join(', ')}"
      end

      run_parallel_checks(test_domains, TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT) do |domain|
        attempt_dns_resolution(domain)
      end
    end

    private

    # Runs connectivity checks in parallel using fiber-based concurrency.
    #
    # This method uses the `async` gem to run multiple checks concurrently with the following behavior:
    # - Returns `true` as soon as ANY check succeeds (early exit optimization)
    # - Returns `false` if ALL checks fail OR the overall timeout is reached
    # - Each individual check runs with its own timeout (defined in the yielded block)
    # - All checks run concurrently within the overall timeout window
    # - Tasks are cancelled as soon as first success is detected (true early exit)
    #
    # Implementation Details:
    # The async gem uses fibers (not threads) for lightweight concurrency. Fibers are:
    # - More memory-efficient than threads (uses cooperative multitasking)
    # - Better for I/O-bound operations like network checks
    # - Scheduled by the Ruby VM rather than the OS
    #
    # Why Async::Barrier?
    # Barrier collects results from all concurrent tasks and provides:
    # - Automatic task lifecycle management (no manual fiber cleanup needed)
    # - Clean cancellation when first success occurs
    # - Exception isolation per task (one failure doesn't crash others)
    #
    # @param items [Array] Collection of items to check (endpoints, domains, etc.)
    # @param overall_timeout [Float] Maximum seconds to wait for any check to succeed
    # @yield [item] Block that performs the actual connectivity test
    # @yieldparam item The current item being tested
    # @yieldreturn [Boolean] true if check succeeded, false otherwise
    # @return [Boolean] true if any check succeeded within timeout, false otherwise
    #
    # @example Testing TCP connectivity to multiple endpoints
    #   endpoints = [
    #     { host: '1.1.1.1', port: 443 },
    #     { host: '8.8.8.8', port: 443 }
    #   ]
    #
    #   success = run_parallel_checks(endpoints, 5.0) do |endpoint|
    #     attempt_tcp_connection(endpoint)
    #   end
    #
    # Performance Characteristics:
    # - Best case: Returns immediately when first check succeeds (~50-200ms)
    # - Worst case: Waits `overall_timeout` seconds when all checks fail
    # - Memory: O(n) where n is number of items (one fiber per item)
    # - CPU: Minimal, as checks are I/O-bound
    #
    def run_parallel_checks(items, overall_timeout)
      return false if items.empty?

      # Async.run creates a new reactor and blocks until completion.
      # The block receives a task object that represents this async operation.
      Async do |task|
        # Set an overall timeout for the entire operation.
        # If this expires, Async::TimeoutError is raised and caught below.
        task.with_timeout(overall_timeout) do
          # Barrier manages a collection of concurrent tasks.
          # It coordinates task execution and cleanup.
          barrier = Async::Barrier.new

          # Flag to track if we've found a success (fiber-safe as explained below)
          success_found = false

          # Shared flag to track success status.
          #
          # Thread-safety note: This boolean flag is safe without mutex protection because:
          # 1. Async uses cooperative (not preemptive) multitasking with fibers
          # 2. Fibers only yield at explicit I/O operations, not during regular Ruby code
          # 3. Boolean assignment is atomic at the Ruby level
          # 4. We only ever set it to true (never back to false), avoiding race conditions
          # 5. The check-and-stop operation completes before another fiber can execute
          #
          # Execution flow:
          #   Fiber A: I/O (yields) → I/O completes → success_found = true (atomic) → barrier.stop
          #   Fiber B: I/O (yields) → still running... → gets cancelled by barrier.stop
          # The assignment and barrier.stop never interleave because they don't contain yield points.

          # Spawn a concurrent fiber for each item.
          # Each fiber runs independently and can succeed/fail without affecting others.
          items.each do |item|
            barrier.async do
              # Call the provided block with the item.
              # The block should return true on success, false on failure.
              result = yield(item)

              # If this check succeeded and we haven't found success yet, stop all tasks
              if result && !success_found
                success_found = true
                # Stop barrier immediately - cancels remaining tasks
                barrier.stop
              end

              result
            rescue => e
              # Catch and log any unexpected errors from the check.
              # Return false to indicate this check failed.
              log_unexpected_error(e)
              false
            end
          end

          # Wait for either:
          # - First success (barrier.stop called)
          # - All tasks to complete (all failed)
          # - Overall timeout (Async::TimeoutError raised)
          barrier.wait

          # Return whether we found any successful check
          success_found
        end
      rescue Async::TimeoutError
        # Overall timeout expired before any check succeeded.
        # This is a normal flow control mechanism, not an error.
        false
      end.wait # Block until the async operation completes and return its result
    end

    # Attempts to establish a TCP connection to a specific endpoint.
    #
    # This method tests basic TCP connectivity (Layer 4 in the OSI model) without
    # requiring DNS resolution. It's useful for testing internet connectivity when
    # DNS might be broken.
    #
    # @param endpoint [Hash] Endpoint configuration with :host and :port keys
    # @option endpoint [String] :host IP address or hostname to connect to
    # @option endpoint [Integer] :port TCP port number to connect to
    # @return [Boolean] true if connection succeeded, false otherwise
    #
    # @example Testing connectivity to Cloudflare DNS
    #   attempt_tcp_connection(host: '1.1.1.1', port: 443)
    #
    # Implementation Notes:
    # - Uses Socket.tcp with connect_timeout for fast failure on unreachable hosts
    # - Wrapped in Timeout.timeout as a safety net for the connection attempt
    # - Connection is immediately closed after success (no data transfer)
    # - All exceptions are caught and converted to false (not an error condition)
    #
    def attempt_tcp_connection(endpoint)
      Timeout.timeout(TimingConstants::TCP_CONNECTION_TIMEOUT) do
        Socket.tcp(endpoint[:host], endpoint[:port],
          connect_timeout: TimingConstants::TCP_CONNECTION_TIMEOUT) do
          @output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
          true
        end
      end
    rescue => e
      @output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}" if @verbose
      false
    end

    # Fast TCP connection attempt optimized for continuous monitoring.
    #
    # Similar to attempt_tcp_connection but with shorter timeout for speed.
    # Used by fast_connectivity? method for quick outage detection.
    #
    # @param endpoint [Hash] Endpoint configuration with :host and :port keys
    # @return [Boolean] true if connection succeeded, false otherwise
    #
    def attempt_fast_tcp_connection(endpoint)
      Timeout.timeout(TimingConstants::FAST_TCP_CONNECTION_TIMEOUT) do
        Socket.tcp(endpoint[:host], endpoint[:port],
          connect_timeout: TimingConstants::FAST_TCP_CONNECTION_TIMEOUT) do
          @output.puts "Fast check: connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
          true
        end
      end
    rescue => e
      @output.puts "Fast check: failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}" if @verbose
      false
    end

    # Attempts to resolve a domain name to an IP address.
    #
    # This method tests DNS functionality by performing a forward lookup of a domain name.
    # It only checks that DNS resolution works, not that the resolved IP is reachable.
    #
    # @param domain [String] Domain name to resolve (e.g., 'google.com')
    # @return [Boolean] true if resolution succeeded, false otherwise
    #
    # @example Testing DNS resolution
    #   attempt_dns_resolution('google.com')  # => true if DNS works
    #
    # Implementation Notes:
    # - Uses IPSocket.getaddress which queries the system's DNS resolver
    # - Returns true if ANY IP address is returned (IPv4 or IPv6)
    # - Wrapped in timeout to prevent hanging on slow/broken DNS servers
    # - All exceptions are caught and converted to false (not an error condition)
    #
    def attempt_dns_resolution(domain)
      Timeout.timeout(TimingConstants::DNS_RESOLUTION_TIMEOUT) do
        IPSocket.getaddress(domain)
        @output.puts "Successfully resolved #{domain}" if @verbose
        true
      end
    rescue => e
      @output.puts "Failed to resolve #{domain}: #{e.class}" if @verbose
      false
    end

    # Logs unexpected errors that occur during connectivity testing.
    #
    # This method is called when an exception is raised during a connectivity check
    # that isn't part of the normal failure path (e.g., programming errors, system issues).
    #
    # @param error [StandardError] The exception that was caught
    # @return [void]
    #
    # @note Only outputs when verbose mode is enabled
    #
    def log_unexpected_error(error)
      return unless @verbose

      @output.puts "Unexpected error during connectivity test: #{error.class} - #{error.message}"
    end

    # Loads the list of TCP endpoints to test for internet connectivity.
    #
    # The endpoints are loaded from a YAML configuration file and cached for the lifetime
    # of this object. The file contains well-known public services that should be reachable
    # from any internet-connected machine (e.g., Cloudflare DNS, Google DNS).
    #
    # @return [Array<Hash>] Array of endpoint hashes with :host and :port keys
    #
    # @example Returned structure
    #   [
    #     { host: '1.1.1.1', port: 443 },
    #     { host: '8.8.8.8', port: 443 }
    #   ]
    #
    # Implementation Notes:
    # - Results are memoized in @tcp_test_endpoints
    # - YAML keys are converted to symbols for cleaner access
    # - File path is relative to this source file location
    #
    def tcp_test_endpoints
      @tcp_test_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'tcp_test_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |endpoint| endpoint.transform_keys(&:to_sym) }
      end
    end

    # Loads the list of domain names to test for DNS functionality.
    #
    # The domains are loaded from a YAML configuration file and cached for the lifetime
    # of this object. The file contains well-known domains that should always be resolvable
    # (e.g., google.com, cloudflare.com).
    #
    # @return [Array<String>] Array of domain names to test
    #
    # @example Returned structure
    #   ['google.com', 'cloudflare.com', 'amazon.com']
    #
    # Implementation Notes:
    # - Results are memoized in @dns_test_domains
    # - Extracts 'domain' field from each YAML entry
    # - File path is relative to this source file location
    #
    def dns_test_domains
      @dns_test_domains ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'dns_test_domains.yml')
        data = YAML.safe_load_file(yaml_path)
        data['domains'].map { |domain| domain['domain'] }
      end
    end
  end
end
