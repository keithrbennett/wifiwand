# frozen_string_literal: true

require_relative '../connectivity_states'
require_relative '../runtime_config'

module WifiWand
  class StatusLineDataBuilder
    DEFAULT_NETWORK_WORKER_RESULT_TIMEOUT_SECONDS = 2
    DEFAULT_CONNECTIVITY_WORKER_RESULT_TIMEOUT_SECONDS = 2
    DEFAULT_WORKER_RESULT_POLL_INTERVAL_SECONDS = 0.01
    DEFAULT_WORKER_CLEANUP_TIMEOUT_SECONDS = 0.05
    # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
    WORKER_BOUNDARY_ERROR = StandardError

    attr_reader :model, :expected_network_errors
    private attr_reader :runtime_config

    def self.call(model, progress_callback: nil, **)
      new(model, **).call(progress_callback: progress_callback)
    end

    def initialize(
      model,
      runtime_config: nil,
      expected_network_errors: [],
      network_worker_result_timeout_seconds: nil,
      connectivity_worker_result_timeout_seconds: nil,
      worker_result_poll_interval_seconds: DEFAULT_WORKER_RESULT_POLL_INTERVAL_SECONDS,
      worker_cleanup_timeout_seconds: DEFAULT_WORKER_CLEANUP_TIMEOUT_SECONDS,
      **kwargs
    )
      @model = model
      @runtime_config = runtime_config || RuntimeConfig.new(
        verbose:    kwargs[:verbose],
        out_stream: kwargs.key?(:out_stream) ? kwargs[:out_stream] : $stdout
      )
      @expected_network_errors = expected_network_errors
      @network_worker_result_timeout_seconds =
        network_worker_result_timeout_seconds || DEFAULT_NETWORK_WORKER_RESULT_TIMEOUT_SECONDS
      @connectivity_worker_result_timeout_seconds =
        connectivity_worker_result_timeout_seconds || DEFAULT_CONNECTIVITY_WORKER_RESULT_TIMEOUT_SECONDS
      @worker_result_poll_interval_seconds = worker_result_poll_interval_seconds
      @worker_cleanup_timeout_seconds = worker_cleanup_timeout_seconds
      @cancellation_mutex = Mutex.new
      reset_worker_cancellation!
      @worker_registry_mutex = Mutex.new
      @worker_deadlines = {}
      @straggler_threads = []
    end

    def out_stream = runtime_config.out_stream

    def call(progress_callback: nil)
      reset_worker_cancellation!
      reap_straggler_threads
      worker_start_time = monotonic_now
      partial = initial_data(worker_start_time)

      progress_callback&.call(partial.dup)

      unless partial[:wifi_on]
        partial.merge!(data_when_wifi_off)
        progress_callback&.call(partial.dup)
        return partial
      end

      result_queue = Queue.new
      network_thread, connectivity_thread = build_status_threads(result_queue, worker_start_time)
      cached_results = {}

      partial.merge!(await_worker_result(result_queue, :network, cached_results, worker_start_time))
      progress_callback&.call(partial.dup)

      partial.merge!(await_worker_result(result_queue, :connectivity, cached_results, worker_start_time))

      final_data = partial.dup
      progress_callback&.call(final_data)
      final_data
    rescue WifiWand::CommandNotFoundError, WifiWand::MethodNotImplementedError
      raise
    rescue *expected_network_errors, WifiWand::Error => e
      out_stream.puts "Warning: status_line_data failed: #{e.class}: #{e.message}" if verbose?
      progress_callback&.call(nil)
      nil
    ensure
      cleanup_worker_threads(network_thread, connectivity_thread)
    end

    private def build_status_threads(result_queue, worker_start_time)
      # Audit note for cleanup risk:
      # - network_identity may block inside model.status_network_identity. On macOS
      #   that can reach helper subprocess I/O and system_profiler reads; on Ubuntu
      #   it can wait on external commands such as iw.
      # - connectivity_data may block inside model.internet_tcp_connectivity?,
      #   model.dns_working?, or model.captive_portal_state. Those probes already run in helper
      #   subprocesses, so this worker mostly waits on bounded pipe reads and helper deadlines.
      [
        spawn_worker(:network, worker_start_time + worker_result_timeout_seconds_for(:network)) do
          publish_worker_result(result_queue, :network) { network_identity(worker_start_time) }
        end,
        spawn_worker(:connectivity, worker_start_time + worker_result_timeout_seconds_for(:connectivity)) do
          publish_worker_result(result_queue, :connectivity) { connectivity_data(worker_start_time) }
        end,
      ]
    end

    private def spawn_worker(worker_name = nil, deadline = nil, &block)
      startup_mutex = Mutex.new
      startup_condition = ConditionVariable.new
      worker_ready = false
      start_allowed = false

      thread = Thread.new do
        startup_mutex.synchronize do
          worker_ready = true
          startup_condition.signal
          startup_condition.wait(startup_mutex) until start_allowed
        end

        begin
          block.call
        ensure
          unregister_worker_thread(Thread.current)
        end
      end

      startup_mutex.synchronize do
        startup_condition.wait(startup_mutex) until worker_ready
        register_worker_thread(thread, worker_name, deadline) if worker_name && deadline
        start_allowed = true
        startup_condition.signal
      end

      thread
    end

    private def publish_worker_result(result_queue, worker_name)
      result_queue << [worker_name, :result, yield]
    rescue WORKER_BOUNDARY_ERROR => e
      # Worker exceptions must cross the Queue boundary so the main status path
      # can apply the same fallback/error rules synchronously.
      result_queue << [worker_name, :error, e]
    end

    private def await_worker_result(result_queue, worker_name, cached_results, worker_start_time)
      if cached_results.key?(worker_name)
        status, payload = cached_results.delete(worker_name)
        raise payload if status == :error

        return payload
      end

      deadline = worker_start_time + worker_result_timeout_seconds_for(worker_name)

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

    private def pop_worker_result_before_deadline(result_queue, deadline)
      loop do
        return result_queue.pop(true)
      rescue ThreadError
        remaining = deadline - monotonic_now
        return nil if remaining <= 0

        sleep([@worker_result_poll_interval_seconds, remaining].min)
      end
    end

    private def worker_result_timeout_seconds_for(worker_name)
      case worker_name
      when :network
        @network_worker_result_timeout_seconds
      when :connectivity
        @connectivity_worker_result_timeout_seconds
      else
        raise ArgumentError, "Unknown worker name: #{worker_name}"
      end
    end

    private def cleanup_worker_threads(*threads)
      cancel_workers!

      threads.compact.each do |thread|
        next unless thread.alive?

        thread.join(worker_cleanup_join_timeout(thread))
        next unless thread.alive?

        out_stream.puts 'Warning: worker thread still running after cancellation request' if verbose?
        track_straggler_thread(thread)
      end
    end

    private def worker_timeout_result(worker_name)
      out_stream.puts "Warning: #{worker_name} status worker timed out" if verbose?
      fallback_worker_result(worker_name)
    end

    private def fallback_worker_result(worker_name)
      case worker_name
      when :network
        {
          connected:      nil,
          network_name:   nil,
          signal_quality: nil,
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

    private def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    private def cancel_workers!
      @cancellation_mutex.synchronize { @cancelled = true }
    end

    private def reset_worker_cancellation!
      @cancellation_mutex.synchronize { @cancelled = false }
    end

    private def cancelled?
      @cancellation_mutex.synchronize { @cancelled }
    end

    private def register_worker_thread(thread, worker_name, deadline)
      @worker_registry_mutex.synchronize do
        @worker_deadlines[thread] = {
          worker_name: worker_name,
          deadline:    deadline,
        }
      end
    end

    private def unregister_worker_thread(thread)
      @worker_registry_mutex.synchronize do
        @worker_deadlines.delete(thread)
      end
    end

    private def worker_cleanup_join_timeout(thread)
      metadata = @worker_registry_mutex.synchronize { @worker_deadlines[thread] }
      return @worker_cleanup_timeout_seconds unless metadata

      deadline_remaining = metadata[:deadline] - monotonic_now
      [deadline_remaining, 0].max + @worker_cleanup_timeout_seconds
    end

    private def track_straggler_thread(thread)
      @worker_registry_mutex.synchronize do
        @straggler_threads << thread unless @straggler_threads.include?(thread)
      end
    end

    private def reap_straggler_threads
      stragglers = @worker_registry_mutex.synchronize { @straggler_threads.dup }
      stragglers.each { |thread| thread.join(@worker_cleanup_timeout_seconds) }

      @worker_registry_mutex.synchronize do
        @straggler_threads.select!(&:alive?)
        @worker_deadlines.select! { |thread, _metadata| thread.alive? }
      end
    end

    def verbose? = runtime_config.verbose

    private def initial_data(worker_start_time)
      deadline = worker_start_time + worker_result_timeout_seconds_for(:network)
      wifi_on = model.status_wifi_on?(timeout_in_secs: remaining_worker_budget(deadline))
      {
        wifi_on:                       wifi_on,
        signal_quality:                nil,
        dns_working:                   nil,
        internet_state:                ConnectivityStates::INTERNET_PENDING,
        internet_check_complete:       false,
        connected:                     :pending,
        network_name:                  :pending,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :unknown,
      }
    end

    private def data_when_wifi_off
      {
        dns_working:                   false,
        connected:                     false,
        network_name:                  nil,
        signal_quality:                nil,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        # WiFi-off means no portal can redirect, but no portal check ran, so
        # keep this aligned with the indeterminate portal state.
        captive_portal_login_required: :unknown,
      }
    end

    private def network_identity(worker_start_time)
      deadline = worker_start_time + worker_result_timeout_seconds_for(:network)
      return cancelled_worker_result(:network) if cancelled?

      model.status_network_identity(
        timeout_in_secs: remaining_worker_budget(deadline)
      )
    rescue WifiWand::CommandTimeoutError
      fallback_worker_result(:network)
    rescue WifiWand::CommandNotFoundError, WifiWand::MethodNotImplementedError
      raise
    rescue WifiWand::CommandExecutor::OsCommandError, WifiWand::CommandSpawnError => e
      out_stream.puts "Warning: network status lookup failed: #{e.class}: #{e.message}" if verbose?
      fallback_worker_result(:network)
    rescue WifiWand::Error, *expected_network_errors => e
      out_stream.puts "Warning: network status lookup failed: #{e.class}: #{e.message}" if verbose?
      {
        connected:      false,
        network_name:   nil,
        signal_quality: nil,
      }
    end

    private def connectivity_data(worker_start_time)
      deadline = worker_start_time + worker_result_timeout_seconds_for(:connectivity)
      return cancelled_worker_result(:connectivity) if cancelled?

      tcp_result = tcp_connectivity_result(deadline)
      return cancelled_worker_result(:connectivity) if cancelled?

      dns_result = dns_working_result(deadline)
      return cancelled_worker_result(:connectivity) if cancelled?

      return fallback_worker_result(:connectivity) if tcp_result[:timed_out]

      unless tcp_result[:success]
        dns_working = dns_result[:timed_out] ? nil : dns_result[:success]
        return data_when_internet_unreachable(dns_working: dns_working)
      end

      return fallback_worker_result(:connectivity) if dns_result[:timed_out]
      return data_when_internet_unreachable(dns_working: dns_result[:success]) unless dns_result[:success]

      portal_state = captive_portal_state(timeout_in_secs: remaining_worker_budget(deadline))
      return cancelled_worker_result(:connectivity) if cancelled?

      {
        dns_working:                   true,
        internet_state:                ConnectivityStates.internet_state_from(
          tcp_working:          true,
          dns_working:          true,
          captive_portal_state: portal_state
        ),
        internet_check_complete:       true,
        captive_portal_state:          portal_state,
        captive_portal_login_required: captive_portal_login_required(portal_state),
      }
    end

    # Cancellation is an internal cleanup path after the caller has already
    # committed to partial data, so we reuse the fallback payload silently
    # instead of emitting an extra timeout warning.
    private def cancelled_worker_result(worker_name)
      fallback_worker_result(worker_name)
    end

    private def tcp_connectivity_result(deadline)
      normalize_probe_result(model.internet_tcp_connectivity?(
        timeout_in_secs: remaining_worker_budget(deadline),
        return_details:  true
      ))
    rescue *expected_network_errors, WifiWand::Error
      { success: false, timed_out: false }
    end

    private def dns_working_result(deadline)
      normalize_probe_result(model.dns_working?(
        timeout_in_secs: remaining_worker_budget(deadline),
        return_details:  true
      ))
    rescue *expected_network_errors, WifiWand::Error
      { success: false, timed_out: false }
    end

    private def captive_portal_state(timeout_in_secs:)
      model.captive_portal_state(timeout_in_secs: timeout_in_secs)
    rescue *expected_network_errors, WifiWand::Error
      ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
    end

    private def remaining_worker_budget(deadline)
      [deadline - monotonic_now, 0].max
    end

    private def normalize_probe_result(result)
      return result if result.is_a?(Hash)

      { success: result == true, timed_out: false }
    end

    private def captive_portal_login_required(portal_state)
      case portal_state
      when ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE
        :unknown
      when ConnectivityStates::CAPTIVE_PORTAL_FREE
        :no
      else
        :yes
      end
    end

    private def data_when_internet_unreachable(dns_working:)
      {
        dns_working:                   dns_working,
        internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
        internet_check_complete:       true,
        captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
        captive_portal_login_required: :unknown,
      }
    end
  end
end
