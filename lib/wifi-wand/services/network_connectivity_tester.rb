# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'socket'
require 'timeout'
require 'yaml'
require 'ipaddr'
require_relative '../timing_constants'
require_relative '../connectivity_states'
require_relative 'captive_portal_checker'

module WifiWand
  class NetworkConnectivityTester
    UNSET = Object.new.freeze

    attr_reader :captive_portal_checker

    def initialize(verbose: false, output: $stdout)
      @verbose = verbose
      @output = output
      @captive_portal_checker = CaptivePortalChecker.new(verbose: verbose, output: output)
    end

    def internet_connectivity_state(tcp_working = nil, dns_working = nil, captive_portal_state = UNSET)
      tcp = tcp_working.nil? ? tcp_connectivity? : tcp_working
      dns = dns_working.nil? ? dns_working? : dns_working
      return ConnectivityStates::INTERNET_UNREACHABLE unless tcp && dns

      captive_portal_state = self.captive_portal_state if captive_portal_state.equal?(UNSET)
      ConnectivityStates.internet_state_from(
        tcp_working:          tcp,
        dns_working:          dns,
        captive_portal_state: captive_portal_state
      )
    end

    def captive_portal_state = @captive_portal_checker.captive_portal_state

    # Fast connectivity check optimized for continuous monitoring commands.
    #
    # This is the cheap "are we probably online right now?" probe used in fast
    # paths such as event logging, where keeping the command responsive matters
    # more than building a full connectivity diagnosis. It intentionally skips DNS
    # and captive-portal checks and instead races a small set of well-known TCP
    # endpoints in parallel.
    #
    # The check preserves the same early-success behavior as the broader internet
    # connectivity methods: it returns +true+ as soon as any endpoint reports a
    # successful TCP connection. If no endpoint succeeds before the overall fast
    # timeout expires, it returns +false+.
    #
    # Unlike the older thread-based implementation, each speculative TCP probe now
    # runs in a short-lived helper subprocess. That gives the parent process a hard
    # cancellation boundary when a resolver or socket syscall stops cooperating,
    # so the public method stays within its documented timeout window even if an
    # individual probe hangs.
    #
    # Endpoints tested:
    # - 1.1.1.1:443 (Cloudflare)
    # - 8.8.8.8:443 (Google)
    # - 180.76.76.76:443 (Baidu)
    #
    # @return [Boolean] true when any fast TCP probe succeeds before the overall
    #   timeout, false otherwise
    #
    # @see tcp_connectivity? for the broader TCP check used in status/info flows
    # @see internet_connectivity_state for the full TCP + DNS + captive portal path
    def fast_connectivity?
      fast_endpoints = [
        { host: '1.1.1.1', port: 443 },
        { host: '8.8.8.8', port: 443 },
        { host: '180.76.76.76', port: 443 },
      ]

      if @verbose
        endpoints_list = fast_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Fast connectivity check to: #{endpoints_list}"
      end

      run_parallel_checks?(
        fast_endpoints,
        TimingConstants::FAST_CONNECTIVITY_TIMEOUT,
        helper_mode: :fast_tcp
      )
    end

    def tcp_connectivity?
      test_endpoints = tcp_test_endpoints

      if @verbose
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Testing internet TCP connectivity to: #{endpoints_list}"
      end

      run_parallel_checks?(
        test_endpoints,
        TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        helper_mode: :tcp
      )
    end

    def dns_working?
      test_domains = dns_test_domains

      @output.puts "Testing DNS resolution for domains: #{test_domains.join(', ')}" if @verbose

      run_parallel_checks?(
        test_domains,
        TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        helper_mode: :dns
      )
    end

    private

    def run_parallel_checks?(items, overall_timeout, helper_mode:)
      return false if items.empty?

      probes = items.filter_map { |item| start_connectivity_probe(item, helper_mode) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + overall_timeout

      while probes.any?
        ready_readers = ready_probe_readers(probes, deadline)
        break if ready_readers.nil? || ready_readers.empty?

        ready_probes = probes.select { |probe| ready_readers.include?(probe[:reader]) }
        ready_probes.each do |probe|
          result = read_probe_result(probe)
          log_probe_result(probe, result)
          finalize_probe(probe)
          probes.delete(probe)
          return true if result[:success]
        end
      end

      false
    ensure
      terminate_probes(probes || [])
    end

    def ready_probe_readers(probes, deadline)
      timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return [] if timeout <= 0

      ready_readers, = IO.select(probes.map { |probe| probe[:reader] }, nil, nil, timeout)
      ready_readers
    end

    def start_connectivity_probe(item, helper_mode)
      reader, writer = IO.pipe
      pid = Process.spawn(*connectivity_probe_command(item, helper_mode), out: writer, err: File::NULL)
      writer.close
      { pid: pid, reader: reader, item: item, helper_mode: helper_mode }
    rescue => e
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      log_helper_start_failure(item, helper_mode, e)
      nil
    end

    def connectivity_probe_command(item, helper_mode)
      [RbConfig.ruby, connectivity_probe_helper_path, helper_mode.to_s,
        *probe_command_args(item, helper_mode)]
    end

    def connectivity_probe_helper_path
      File.join(File.dirname(__FILE__), 'network_connectivity_probe_helper.rb')
    end

    def probe_command_args(item, helper_mode)
      case helper_mode
      when :tcp, :fast_tcp
        [item[:host], item[:port].to_s]
      when :dns
        [item]
      else
        raise ArgumentError, "Unsupported helper mode: #{helper_mode}"
      end
    end

    def read_probe_result(probe)
      payload = JSON.parse(probe[:reader].read.to_s.strip, symbolize_names: true)
      { success: payload[:success] == true, error_class: payload[:error_class] }
    rescue => e
      { success: false, error_class: e.class.to_s }
    end

    def log_probe_result(probe, result)
      return unless @verbose

      case probe[:helper_mode]
      when :tcp
        log_tcp_probe_result(probe[:item], result)
      when :fast_tcp
        log_fast_tcp_probe_result(probe[:item], result)
      when :dns
        log_dns_probe_result(probe[:item], result)
      end
    end

    def log_tcp_probe_result(endpoint, result)
      if result[:success]
        @output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}"
      else
        @output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{result[:error_class]}"
      end
    end

    def log_fast_tcp_probe_result(endpoint, result)
      if result[:success]
        @output.puts "Fast check: connected to #{endpoint[:host]}:#{endpoint[:port]}"
      else
        @output.puts "Fast check: failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: " \
          "#{result[:error_class]}"
      end
    end

    def log_dns_probe_result(domain, result)
      if result[:success]
        @output.puts "Successfully resolved #{domain}"
      else
        @output.puts "Failed to resolve #{domain}: #{result[:error_class]}"
      end
    end

    def log_helper_start_failure(item, helper_mode, error)
      return unless @verbose

      target = case helper_mode
               when :tcp, :fast_tcp then "#{item[:host]}:#{item[:port]}"
               when :dns then item
               else item.inspect
      end
      @output.puts "Failed to start #{helper_mode} helper for #{target}: #{error.class}"
    end

    def terminate_probes(probes)
      probes.each { |probe| terminate_probe(probe) }
    end

    def terminate_probe(probe)
      pid = probe[:pid]
      return unless pid

      Process.kill('TERM', pid)
      Process.kill('KILL', pid)
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
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.05

      loop do
        return if reap_probe(pid)
        return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(0.005)
      end
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def attempt_tcp_connection(endpoint)
      Timeout.timeout(TimingConstants::TCP_CONNECTION_TIMEOUT) do
        Socket.tcp(
          endpoint[:host],
          endpoint[:port],
          connect_timeout: TimingConstants::TCP_CONNECTION_TIMEOUT
        ) do
          @output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
          true
        end
      end
    rescue => e
      @output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}" if @verbose
      false
    end

    def attempt_fast_tcp_connection(endpoint)
      Timeout.timeout(TimingConstants::FAST_TCP_CONNECTION_TIMEOUT) do
        Socket.tcp(
          endpoint[:host],
          endpoint[:port],
          connect_timeout: TimingConstants::FAST_TCP_CONNECTION_TIMEOUT
        ) do
          @output.puts "Fast check: connected to #{endpoint[:host]}:#{endpoint[:port]}" if @verbose
          true
        end
      end
    rescue => e
      if @verbose
        @output.puts "Fast check: failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{e.class}"
      end
      false
    end

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

    def log_unexpected_error(error)
      return unless @verbose

      @output.puts "Unexpected error during connectivity test: #{error.class} - #{error.message}"
    end

    def tcp_test_endpoints
      @tcp_test_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'tcp_test_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |endpoint| endpoint.transform_keys(&:to_sym) }
      end
    end

    def dns_test_domains
      @dns_test_domains ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'dns_test_domains.yml')
        data = YAML.safe_load_file(yaml_path)
        data['domains'].map { |domain| domain['domain'] }
      end
    end
  end
end
