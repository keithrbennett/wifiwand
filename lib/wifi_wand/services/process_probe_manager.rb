# frozen_string_literal: true

module WifiWand
  module ProcessProbeManager
    def helper_result_grace
      return self.class::HELPER_RESULT_GRACE if self.class.const_defined?(:HELPER_RESULT_GRACE, false)

      raise NotImplementedError,
        "#{self.class} must define HELPER_RESULT_GRACE to include ProcessProbeManager"
    end

    def helper_exit_poll_interval
      0.01
    end

    def terminate_probes(probes, grace: helper_result_grace)
      probes.each { |probe| terminate_probe(probe, grace: grace) }
    end

    def terminate_probe(probe, grace: helper_result_grace)
      pid = probe[:pid]
      return unless pid

      Process.kill('TERM', pid)
      wait_for_probe_exit(pid, grace: grace)
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

    def wait_for_probe_exit(pid, grace: helper_result_grace)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + grace

      loop do
        return if reap_probe(pid)

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0

        sleep([helper_exit_poll_interval, remaining].min)
      end

      Process.kill('KILL', pid)
      reap_probe(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end
