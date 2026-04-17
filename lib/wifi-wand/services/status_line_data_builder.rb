# frozen_string_literal: true

require_relative '../connectivity_states'

module WifiWand
  class StatusLineDataBuilder
    SSID_UNAVAILABLE_LABEL = '[SSID unavailable]'
    DEFAULT_WORKER_RESULT_TIMEOUT_SECONDS = 2
    DEFAULT_WORKER_RESULT_POLL_INTERVAL_SECONDS = 0.01
    DEFAULT_WORKER_CLEANUP_TIMEOUT_SECONDS = 0.05

    attr_reader :model, :verbose_mode, :output, :expected_network_errors

    def initialize(
      model,
      verbose: false,
      output: $stdout,
      expected_network_errors: [],
      worker_result_timeout_seconds: DEFAULT_WORKER_RESULT_TIMEOUT_SECONDS,
      worker_result_poll_interval_seconds: DEFAULT_WORKER_RESULT_POLL_INTERVAL_SECONDS,
      worker_cleanup_timeout_seconds: DEFAULT_WORKER_CLEANUP_TIMEOUT_SECONDS
    )
      @model = model
      @verbose_mode = verbose
      @output = output
      @expected_network_errors = expected_network_errors
      @worker_result_timeout_seconds = worker_result_timeout_seconds
      @worker_result_poll_interval_seconds = worker_result_poll_interval_seconds
      @worker_cleanup_timeout_seconds = worker_cleanup_timeout_seconds
    end

    def call(progress_callback: nil)
      partial = initial_data

      progress_callback&.call(partial.dup)

      unless partial[:wifi_on]
        partial.merge!(data_when_wifi_off)
        progress_callback&.call(partial.dup)
        return partial
      end

      result_queue = Queue.new
      network_thread, connectivity_thread = build_status_threads(result_queue)
      cached_results = {}

      partial.merge!(await_worker_result(result_queue, :network, cached_results))
      progress_callback&.call(partial.dup)

      partial.merge!(await_worker_result(result_queue, :connectivity, cached_results))

      final_data = partial.dup
      progress_callback&.call(final_data)
      final_data
    rescue *expected_network_errors, WifiWand::Error => e
      output.puts "Warning: status_line_data failed: #{e.class}: #{e.message}" if verbose_mode
      progress_callback&.call(nil)
      nil
    ensure
      cleanup_worker_threads(network_thread, connectivity_thread)
    end

    private

    def build_status_threads(result_queue)
      [
        spawn_worker { publish_worker_result(result_queue, :network) { network_identity } },
        spawn_worker { publish_worker_result(result_queue, :connectivity) { connectivity_data } },
      ]
    end

    def spawn_worker(&) = Thread.new(&)

    def publish_worker_result(result_queue, worker_name)
      result_queue << [worker_name, :result, yield]
    rescue => e
      result_queue << [worker_name, :error, e]
    end

    def await_worker_result(result_queue, worker_name, cached_results)
      if cached_results.key?(worker_name)
        status, payload = cached_results.delete(worker_name)
        raise payload if status == :error

        return payload
      end

      deadline = monotonic_now + @worker_result_timeout_seconds

      loop do
        queue_entry = pop_worker_result_before_deadline(result_queue, deadline)
        return worker_timeout_result(worker_name) if queue_entry.nil?

        completed_worker, status, payload = queue_entry

        if completed_worker == worker_name
          raise payload if status == :error

          return payload
        end

        cached_results[completed_worker] = [status, payload]
      end
    end

    def pop_worker_result_before_deadline(result_queue, deadline)
      loop do
        return result_queue.pop(true)
      rescue ThreadError
        remaining = deadline - monotonic_now
        return nil if remaining <= 0

        sleep([@worker_result_poll_interval_seconds, remaining].min)
      end
    end

    def cleanup_worker_threads(*threads)
      threads.compact.each do |thread|
        thread.kill if thread.alive?
        thread.join(@worker_cleanup_timeout_seconds)
      end
    end

    def worker_timeout_result(worker_name)
      output.puts "Warning: #{worker_name} status worker timed out" if verbose_mode

      case worker_name
      when :network
        {
          connected:    nil,
          network_name: nil,
        }
      when :connectivity
        {
          dns_working:                   nil,
          internet_state:                ConnectivityStates::INTERNET_INDETERMINATE,
          internet_check_complete:       true,
          captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
          captive_portal_login_required: :unknown,
        }
      else
        {}
      end
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def initial_data
      {
        wifi_on:                       model.wifi_on?,
        dns_working:                   nil,
        internet_state:                ConnectivityStates::INTERNET_PENDING,
        internet_check_complete:       false,
        connected:                     :pending,
        network_name:                  :pending,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :unknown,
      }
    end

    def data_when_wifi_off
      {
        dns_working:                   false,
        connected:                     false,
        network_name:                  nil,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :no,
      }
    end

    def network_identity
      connected = connected?
      network_name = connected ? network_name_for_connected_state : nil

      {
        connected:    connected,
        network_name: network_name,
      }
    rescue WifiWand::Error, *expected_network_errors => e
      output.puts "Warning: network status lookup failed: #{e.class}: #{e.message}" if verbose_mode
      {
        connected:    false,
        network_name: nil,
      }
    end

    def network_name_for_connected_state
      network_name = model.connected_network_name
      return network_name unless network_name.nil? || network_name.to_s.empty?

      SSID_UNAVAILABLE_LABEL
    end

    def connected?
      model.connected?
    end

    def connectivity_data
      tcp_working = tcp_connectivity?
      dns_working = dns_working?

      return data_when_internet_unreachable(dns_working: dns_working) unless tcp_working && dns_working

      portal_state = captive_portal_state

      {
        dns_working:                   dns_working,
        internet_state:                ConnectivityStates.internet_state_from(
          tcp_working:          tcp_working,
          dns_working:          dns_working,
          captive_portal_state: portal_state
        ),
        internet_check_complete:       true,
        captive_portal_state:          portal_state,
        captive_portal_login_required: captive_portal_login_required(portal_state),
      }
    end

    def tcp_connectivity?
      model.internet_tcp_connectivity?
    rescue *expected_network_errors, WifiWand::Error
      false
    end

    def dns_working?
      model.dns_working?
    rescue *expected_network_errors, WifiWand::Error
      false
    end

    def captive_portal_state
      model.captive_portal_state
    rescue *expected_network_errors, WifiWand::Error
      ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
    end

    def captive_portal_login_required(portal_state)
      case portal_state
      when ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
        :unknown
      when ConnectivityStates::CAPTIVE_PORTAL_FREE
        :no
      else
        :yes
      end
    end

    def data_when_internet_unreachable(dns_working:)
      {
        dns_working:                   dns_working,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :no,
      }
    end
  end
end
