# frozen_string_literal: true

require 'json'
require_relative 'network_connectivity_tester'

module WifiWand
  module NetworkConnectivityProbeHelper
    # StandardError excludes process-control and VM-level exceptions like Interrupt, SystemExit, and NoMemoryError.
    HELPER_PROCESS_BOUNDARY_ERROR = StandardError

    def self.parse_argv(argv)
      mode_arg, items_json, timeout_arg = argv
      mode = parse_mode(mode_arg)
      items = JSON.parse(items_json, symbolize_names: true)
      raise ArgumentError, 'probe items must be an array' unless items.is_a?(Array)

      { mode: mode, items: items, timeout: Float(timeout_arg) }
    end

    def self.run(argv, output: $stdout, tester: nil)
      probe = parse_argv(argv)
      tester ||= NetworkConnectivityTester.new(verbose: false, output: $stderr)
      result = parallel_probe_result(
        tester,
        probe[:mode],
        probe[:items],
        probe[:timeout]
      )
      output.print(JSON.generate(result))
      output.flush
    rescue HELPER_PROCESS_BOUNDARY_ERROR => e
      # Subprocess boundary: always return JSON so the parent can treat helper
      # failures as indeterminate connectivity instead of hanging on bad output.
      output.print(JSON.generate(
        success:       false,
        timed_out:     false,
        error_class:   e.class.to_s,
        error_message: e.message
      ))
      output.flush
    end

    def self.parallel_probe_result(tester, mode, items, overall_timeout)
      return batch_result(false, false, []) if items.empty?

      result_queue = Queue.new
      threads = items.map { |item| start_probe_thread(tester, mode, item, result_queue) }
      deadline = current_time + overall_timeout
      pending_results = threads.length
      probe_results = []

      while pending_results.positive?
        remaining_time = deadline - current_time
        return batch_result(false, true, probe_results) if remaining_time <= 0

        result = result_queue.pop(timeout: remaining_time)
        return batch_result(false, true, probe_results) if result.nil?

        pending_results -= 1
        probe_results << result
        return batch_result(true, false, probe_results) if result[:success]
      end

      batch_result(false, false, probe_results)
    ensure
      cleanup_threads(threads || [])
    end

    def self.start_probe_thread(tester, mode, item, result_queue)
      Thread.new do
        Thread.current.report_on_exception = false
        result_queue << probe_result(tester, mode, item)
      rescue HELPER_PROCESS_BOUNDARY_ERROR => e
        # Probe worker boundary: one failing endpoint should not hide results
        # from other endpoints in the same helper process.
        result_queue << { target: item, success: false, error_class: e.class.to_s }
      end
    end
    private_class_method :start_probe_thread

    def self.probe_result(tester, mode, item)
      result = tester.run_probe_result(mode, item)
      result = { success: result == true } unless result.is_a?(Hash)

      {
        target:      item,
        success:     result[:success] == true,
        error_class: result[:error_class],
      }
    end
    private_class_method :probe_result

    def self.batch_result(success, timed_out, probe_results)
      { success: success, timed_out: timed_out, probe_results: probe_results }
    end
    private_class_method :batch_result

    def self.cleanup_threads(threads)
      threads.each do |thread|
        thread.kill if thread.alive?
        thread.join(0.01)
      end
    end
    private_class_method :cleanup_threads

    def self.parse_mode(mode_arg)
      case mode_arg
      when 'tcp'
        :tcp
      when 'dns'
        :dns
      else
        raise ArgumentError, 'mode must be tcp or dns'
      end
    end
    private_class_method :parse_mode

    def self.current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :current_time
  end
end

if $PROGRAM_NAME == __FILE__
  WifiWand::NetworkConnectivityProbeHelper.run(ARGV)
  exit!(0)
end
