# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'socket'
require 'timeout'
require 'yaml'
require_relative '../timing_constants'
require_relative '../connectivity_states'
require_relative '../runtime_config'
require_relative 'captive_portal_checker'
require_relative 'process_probe_manager'

module WifiWand
  class NetworkConnectivityTester
    include ProcessProbeManager

    UNSET = Object.new.freeze
    HELPER_RESULT_GRACE = 0

    attr_reader :captive_portal_checker
    private attr_reader :runtime_config

    def initialize(verbose: false, output: $stdout, runtime_config: nil)
      @runtime_config = runtime_config || RuntimeConfig.new(
        verbose:    verbose,
        out_stream: output
      )
      @captive_portal_checker = CaptivePortalChecker.new(
        runtime_config: @runtime_config
      )
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

    def tcp_connectivity?(timeout_in_secs: nil, overall_timeout: nil, return_details: false)
      test_endpoints = tcp_test_endpoints

      if verbose?
        endpoints_list = test_endpoints.map { |e| "#{e[:host]}:#{e[:port]}" }.join(', ')
        output.puts "Testing internet TCP connectivity to: #{endpoints_list}"
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

      output.puts "Testing DNS resolution for domains: #{test_domains.join(', ')}" if verbose?

      result = parallel_check_result(
        test_domains,
        resolved_timeout(timeout_in_secs, overall_timeout, TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT),
        helper_mode: :dns
      )
      return result if return_details

      result[:success]
    end

    # Detailed single-probe interface used by the connectivity helper process.
    #
    # @param mode [Symbol] one of :tcp or :dns
    # @param target [Hash, String] endpoint hash for TCP modes or domain for DNS
    # @return [Hash] probe result including :success and optional :error_class
    def run_probe_result(mode, target)
      case mode
      when :tcp
        attempt_tcp_connection(target)
      when :dns
        attempt_dns_resolution(target)
      else
        raise ArgumentError, "Unsupported probe mode: #{mode}"
      end
    end

    private def parallel_check_result(items, overall_timeout, helper_mode:)
      return { success: false, timed_out: false } if items.empty?

      probe = start_connectivity_probe(items, helper_mode, overall_timeout)
      return { success: false, timed_out: false } unless probe

      deadline = current_time + overall_timeout
      timed_out = false

      loop do
        ready_readers = ready_probe_readers([probe], deadline)
        if ready_readers.nil? || ready_readers.empty?
          timed_out = deadline_exceeded?(deadline)
          break
        end

        result = read_probe_result(probe)
        next unless result

        log_probe_results(probe[:helper_mode], result[:probe_results])
        finalize_probe(probe)
        probe = nil
        return { success: result[:success], timed_out: result[:timed_out] == true }
      end

      { success: false, timed_out: timed_out }
    ensure
      terminate_probe(probe, grace: 0) if probe
    end

    private def start_connectivity_probe(items, helper_mode, overall_timeout)
      reader, writer = IO.pipe
      pid = Process.spawn(
        *connectivity_probe_command(items, helper_mode, overall_timeout),
        out: writer,
        err: File::NULL
      )
      writer.close
      { pid: pid, reader: reader, helper_mode: helper_mode, buffer: +'', eof: false }
    rescue SystemCallError, IOError => e
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
      log_helper_start_failure(helper_mode, e)
      nil
    end

    private def connectivity_probe_command(items, helper_mode, overall_timeout)
      [
        RbConfig.ruby,
        connectivity_probe_helper_path,
        helper_mode.to_s,
        JSON.generate(items),
        overall_timeout.to_s,
      ]
    end

    private def connectivity_probe_helper_path
      File.join(File.dirname(__FILE__), 'network_connectivity_probe_helper.rb')
    end

    private def ready_probe_readers(probes, deadline)
      timeout = deadline - current_time
      return [] if timeout <= 0

      ready_readers, = IO.select(probes.map { |probe| probe[:reader] }, nil, nil, timeout)
      ready_readers
    end

    private def read_probe_result(probe)
      drain_probe_reader(probe)
      payload_text = probe[:buffer].strip

      return failure_probe_result(EOFError) if probe[:eof] && payload_text.empty?

      payload = JSON.parse(payload_text, symbolize_names: true)
      return failure_probe_result(TypeError) unless payload.is_a?(Hash)

      {
        success:       payload[:success] == true,
        timed_out:     payload[:timed_out] == true,
        error_class:   payload[:error_class],
        probe_results: normalize_helper_probe_results(payload[:probe_results]),
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
      { success: false, timed_out: false, error_class: error_class.to_s, probe_results: [] }
    end

    private def log_helper_start_failure(helper_mode, error)
      return unless verbose?

      output.puts "Failed to start #{helper_mode} connectivity helper: #{error.class}"
    end

    private def normalize_helper_probe_results(raw_results)
      return [] unless raw_results.is_a?(Array)

      raw_results.filter_map do |result|
        next unless result.is_a?(Hash)

        target = result[:target]
        {
          target:      normalize_helper_probe_target(target),
          success:     result[:success] == true,
          error_class: result[:error_class],
        }
      end
    end

    private def normalize_helper_probe_target(target)
      return target.transform_keys(&:to_sym) if target.is_a?(Hash)

      target
    end

    private def log_probe_results(helper_mode, probe_results)
      return unless verbose?

      probe_results.each do |result|
        case helper_mode
        when :tcp
          log_tcp_probe_result(result[:target], result)
        when :dns
          log_dns_probe_result(result[:target], result)
        end
      end
    end

    private def log_tcp_probe_result(endpoint, result)
      endpoint = normalize_tcp_endpoint(endpoint)

      if result[:success]
        output.puts "Successfully connected to #{endpoint[:host]}:#{endpoint[:port]}"
      else
        output.puts "Failed to connect to #{endpoint[:host]}:#{endpoint[:port]}: #{result[:error_class]}"
      end
    end

    private def log_dns_probe_result(domain, result)
      if result[:success]
        output.puts "Successfully resolved #{domain}"
      else
        output.puts "Failed to resolve #{domain}: #{result[:error_class]}"
      end
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

    private def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    private def attempt_tcp_connection(endpoint)
      endpoint = normalize_tcp_endpoint(endpoint)
      Timeout.timeout(TimingConstants::TCP_CONNECTION_TIMEOUT) do
        Socket.tcp(
          endpoint[:host],
          endpoint[:port],
          connect_timeout: TimingConstants::TCP_CONNECTION_TIMEOUT
        ) do
          { success: true }
        end
      end
    rescue SocketError, SystemCallError, IOError, Timeout::Error => e
      { success: false, error_class: e.class.to_s }
    end

    private def attempt_dns_resolution(domain)
      Timeout.timeout(TimingConstants::DNS_RESOLUTION_TIMEOUT) do
        IPSocket.getaddress(domain)
        { success: true }
      end
    rescue SocketError, SystemCallError, Timeout::Error => e
      { success: false, error_class: e.class.to_s }
    end

    private def normalize_tcp_endpoint(endpoint)
      endpoint.transform_keys(&:to_sym)
    end

    private def log_unexpected_error(error)
      return unless verbose?

      output.puts "Unexpected error during connectivity test: #{error.class} - #{error.message}"
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

    private def verbose? = runtime_config.verbose

    private def output = runtime_config.out_stream
  end
end
