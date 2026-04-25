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

    def internet_connectivity_state(tcp_working = nil, dns_working = nil, captive_portal_state = UNSET,
      timeout_in_secs: nil)
      deadline = timeout_in_secs && (current_time + timeout_in_secs)

      tcp_result = probe_result_for(
        tcp_working,
        deadline:      deadline,
        stage_timeout: TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        probe_method:  :tcp_connectivity?
      )
      return ConnectivityStates::INTERNET_INDETERMINATE if tcp_result[:timed_out]
      return ConnectivityStates::INTERNET_UNREACHABLE unless tcp_result[:success]

      dns_result = probe_result_for(
        dns_working,
        deadline:      deadline,
        stage_timeout: TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT,
        probe_method:  :dns_working?
      )
      return ConnectivityStates::INTERNET_INDETERMINATE if dns_result[:timed_out]
      return ConnectivityStates::INTERNET_UNREACHABLE unless dns_result[:success]

      if captive_portal_state.equal?(UNSET)
        remaining_time = deadline ? remaining_time_until(deadline) : nil
        return ConnectivityStates::INTERNET_INDETERMINATE if deadline && remaining_time <= 0

        captive_portal_state = self.captive_portal_state(timeout_in_secs: remaining_time)
      end
      ConnectivityStates.internet_state_from(
        tcp_working:          true,
        dns_working:          true,
        captive_portal_state: captive_portal_state
      )
    end

    def captive_portal_state(timeout_in_secs: nil)
      @captive_portal_checker.captive_portal_state(timeout_in_secs: timeout_in_secs)
    end

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
    def fast_connectivity?(timeout_in_secs: nil, overall_timeout: nil, return_details: false)
      fast_endpoints = [
        { host: '1.1.1.1', port: 443 },
        { host: '8.8.8.8', port: 443 },
        { host: '180.76.76.76', port: 443 },
      ]

      if @verbose
        endpoints_list = fast_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Fast connectivity check to: #{endpoints_list}"
      end

      result = parallel_check_result(
        fast_endpoints,
        resolved_timeout(timeout_in_secs, overall_timeout, TimingConstants::FAST_CONNECTIVITY_TIMEOUT),
        helper_mode: :fast_tcp
      )
      return result if return_details

      result[:success]
    end

    def tcp_connectivity?(timeout_in_secs: nil, overall_timeout: nil, return_details: false)
      test_endpoints = tcp_test_endpoints

      if @verbose
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        @output.puts "Testing internet TCP connectivity to: #{endpoints_list}"
      end

      result = parallel_check_result(
        test_endpoints,
        resolved_timeout(timeout_in_secs, overall_timeout, TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT),
        helper_mode: :tcp
      )
      return result if return_details

      result[:success]
    end

    def dns_working?(timeout_in_secs: nil, overall_timeout: nil, return_details: false)
      test_domains = dns_test_domains

      @output.puts "Testing DNS resolution for domains: #{test_domains.join(', ')}" if @verbose

      result = parallel_check_result(
        test_domains,
        resolved_timeout(timeout_in_secs, overall_timeout, TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT),
        helper_mode: :dns
      )
      return result if return_details

      result[:success]
    end

    # Shared probe interface used by the helper subprocess wrapper.
    #
    # @param mode [Symbol] one of :tcp, :fast_tcp, or :dns
    # @param target [Hash, String] endpoint hash for TCP modes or domain for DNS
    # @return [Boolean] true when the probe succeeds, false otherwise
    def run_probe(mode, target)
      case mode
      when :tcp
        attempt_tcp_connection(target)
      when :fast_tcp
        attempt_fast_tcp_connection(target)
      when :dns
        attempt_dns_resolution(target)
      else
        raise ArgumentError, "Unsupported probe mode: #{mode}"
      end
    end

    private def parallel_check_result(items, overall_timeout, helper_mode:)
      return { success: false, timed_out: false } if items.empty?

      probes = items.filter_map { |item| start_connectivity_probe(item, helper_mode) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + overall_timeout
      terminate_grace = constrained_timeout?(overall_timeout, helper_mode) ? 0 : helper_result_grace
      timed_out = false

      while probes.any?
        ready_readers = ready_probe_readers(probes, deadline)
        if ready_readers.nil? || ready_readers.empty?
          timed_out = deadline_exceeded?(deadline)
          break
        end

        ready_probes = probes.select { |probe| ready_readers.include?(probe[:reader]) }
        ready_probes.each do |probe|
          result = read_probe_result(probe)
          # The helper may have only written a partial JSON payload so far.
          # Keep it alive until EOF so we don't treat an in-flight write as a failure.
          next unless result

          log_probe_result(probe, result)
          finalize_probe(probe)
          probes.delete(probe)
          return { success: true, timed_out: false } if result[:success]
        end
      end

      { success: false, timed_out: timed_out }
    ensure
      terminate_probes(probes || [], grace: terminate_grace || helper_result_grace)
    end

    private def ready_probe_readers(probes, deadline)
      timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return [] if timeout <= 0

      ready_readers, = IO.select(probes.map { |probe| probe[:reader] }, nil, nil, timeout)
      ready_readers
    end

    private def probe_result_for(value, deadline:, stage_timeout:, probe_method:)
      return { success: value, timed_out: false } unless value.nil?
      return { success: false, timed_out: true } if deadline && remaining_time_until(deadline) <= 0

      timeout = remaining_probe_timeout(deadline, stage_timeout)
      begin
        result = normalize_probe_result(public_send(
          probe_method,
          overall_timeout: timeout,
          return_details:  true
        ))
      rescue ArgumentError => e
        raise unless e.message.include?('unknown keyword: :return_details')

        result = normalize_probe_result(public_send(probe_method, overall_timeout: timeout))
      ensure
        if defined?(result) && deadline && remaining_time_until(deadline) <= 0 && !result[:success]
          result = result.merge(timed_out: true)
        end
      end

      result
    end

    private def normalize_probe_result(result)
      return result if result.is_a?(Hash)

      { success: result == true, timed_out: false }
    end

    private def resolved_timeout(timeout_in_secs, overall_timeout, default_timeout)
      timeout_in_secs || overall_timeout || default_timeout
    end

    private def remaining_probe_timeout(deadline, stage_timeout)
      return stage_timeout unless deadline

      [stage_timeout, remaining_time_until(deadline)].min
    end

    private def remaining_time_until(deadline)
      deadline - current_time
    end

    private def deadline_exceeded?(deadline)
      remaining_time_until(deadline) <= 0
    end

    private def constrained_timeout?(overall_timeout, helper_mode)
      overall_timeout < default_timeout_for(helper_mode)
    end

    private def default_timeout_for(helper_mode)
      case helper_mode
      when :fast_tcp
        TimingConstants::FAST_CONNECTIVITY_TIMEOUT
      when :tcp, :dns
        TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT
      else
        raise ArgumentError, "Unsupported helper mode: #{helper_mode}"
      end
    end

    private def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    private def start_connectivity_probe(item, helper_mode)
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

    private def connectivity_probe_command(item, helper_mode)
      [RbConfig.ruby, connectivity_probe_helper_path, helper_mode.to_s,
        *probe_command_args(item, helper_mode)]
    end

    private def connectivity_probe_helper_path
      File.join(File.dirname(__FILE__), 'network_connectivity_probe_helper.rb')
    end

    private def probe_command_args(item, helper_mode)
      case helper_mode
      when :tcp, :fast_tcp
        [item[:host], item[:port].to_s]
      when :dns
        [item]
      else
        raise ArgumentError, "Unsupported helper mode: #{helper_mode}"
      end
    end

    private def read_probe_result(probe)
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
    private def drain_probe_reader(probe)
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

    private def failure_probe_result(error_class)
      { success: false, error_class: error_class.to_s }
    end

    private def log_probe_result(probe, result)
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

    private def log_tcp_probe_result(endpoint, result)
      if result[:success]
        @output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}"
      else
        @output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{result[:error_class]}"
      end
    end

    private def log_fast_tcp_probe_result(endpoint, result)
      if result[:success]
        @output.puts "Fast check: connected to #{endpoint[:host]}:#{endpoint[:port]}"
      else
        @output.puts "Fast check: failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: " \
          "#{result[:error_class]}"
      end
    end

    private def log_dns_probe_result(domain, result)
      if result[:success]
        @output.puts "Successfully resolved #{domain}"
      else
        @output.puts "Failed to resolve #{domain}: #{result[:error_class]}"
      end
    end

    private def log_helper_start_failure(item, helper_mode, error)
      return unless @verbose

      target = case helper_mode
               when :tcp, :fast_tcp then "#{item[:host]}:#{item[:port]}"
               when :dns then item
               else item.inspect
      end
      @output.puts "Failed to start #{helper_mode} helper for #{target}: #{error.class}"
    end

    private def helper_exit_poll_interval
      0.005
    end

    private def attempt_tcp_connection(endpoint)
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

    private def attempt_fast_tcp_connection(endpoint)
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

    private def attempt_dns_resolution(domain)
      Timeout.timeout(TimingConstants::DNS_RESOLUTION_TIMEOUT) do
        IPSocket.getaddress(domain)
        @output.puts "Successfully resolved #{domain}" if @verbose
        true
      end
    rescue => e
      @output.puts "Failed to resolve #{domain}: #{e.class}" if @verbose
      false
    end

    private def log_unexpected_error(error)
      return unless @verbose

      @output.puts "Unexpected error during connectivity test: #{error.class} - #{error.message}"
    end

    private def tcp_test_endpoints
      @tcp_test_endpoints ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'tcp_test_endpoints.yml')
        data = YAML.safe_load_file(yaml_path)
        data['endpoints'].map { |endpoint| endpoint.transform_keys(&:to_sym) }
      end
    end

    private def dns_test_domains
      @dns_test_domains ||= begin
        yaml_path = File.join(File.dirname(__FILE__), '..', 'data', 'dns_test_domains.yml')
        data = YAML.safe_load_file(yaml_path)
        data['domains'].map { |domain| domain['domain'] }
      end
    end
  end
end
