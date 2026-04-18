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
require_relative 'process_probe_manager'

module WifiWand
  class NetworkConnectivityTester
    include ProcessProbeManager

    UNSET = Object.new.freeze
    HELPER_RESULT_GRACE = 0.05

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
          # The helper may have only written a partial JSON payload so far.
          # Keep it alive until EOF so we don't treat an in-flight write as a failure.
          next unless result

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
      { pid: pid, reader: reader, item: item, helper_mode: helper_mode, buffer: +'', eof: false }
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
      drain_probe_reader(probe)
      payload_text = probe[:buffer].strip

      # An EOF with no payload means the helper exited without reporting
      # anything usable, so treat it as a failed probe rather than retrying.
      return failure_probe_result(EOFError) if probe[:eof] && payload_text.empty?

      payload = JSON.parse(payload_text, symbolize_names: true)
      { success: payload[:success] == true, error_class: payload[:error_class] }
    rescue JSON::ParserError
      # Partial JSON is expected while the child is still writing. Only convert
      # parse errors into failures once the pipe has reached EOF and no more
      # bytes can arrive to complete the payload.
      return nil unless probe[:eof]

      failure_probe_result(JSON::ParserError)
    rescue => e
      failure_probe_result(e.class)
    end

    # Drains all bytes that are immediately available from a helper's stdout
    # pipe into the probe buffer without blocking for more. In this context,
    # "draining" means repeatedly consuming the currently readable pipe data
    # until the kernel reports either "nothing else is ready yet" or EOF.
    #
    # We need this because IO.select only tells us the pipe became readable,
    # not that the child finished writing a complete JSON payload. A blocking
    # read here can still hang waiting for EOF, so we accumulate available
    # chunks incrementally and let the caller decide whether to wait for more
    # bytes or parse the completed payload.
    def drain_probe_reader(probe)
      loop do
        # read_nonblock avoids hanging here after IO.select reports readability;
        # a pipe can become readable before the child has closed stdout.
        chunk = probe[:reader].read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable
          # We drained the bytes that were immediately available. Leave any
          # partial payload in the per-probe buffer and wait for the next
          # readiness notification or EOF.
          return
        when nil
          # nil from read_nonblock means the writer side is closed. Mark EOF so
          # the caller knows whether an incomplete JSON buffer is now final.
          probe[:eof] = true
          return
        else
          # Helpers emit tiny JSON payloads, but buffering incrementally keeps
          # this safe if the OS splits the write across multiple pipe reads.
          probe[:buffer] << chunk
        end
      end
    end

    def failure_probe_result(error_class)
      { success: false, error_class: error_class.to_s }
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
