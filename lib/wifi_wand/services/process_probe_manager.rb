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

    # Forces termination of a probe process. Sends SIGTERM, waits for grace,
    # then escalates to SIGKILL if necessary. Always ensures the reader pipe
    # is closed and the PID is cleared from the probe hash.
    def terminate_probe(probe, grace: helper_result_grace)
      pid = probe[:pid]
      probe[:reader]&.close unless probe[:reader]&.closed?
      return unless pid

      Process.kill('TERM', pid)
      wait_for_probe_exit(pid, grace: grace)
      probe[:pid] = nil
    rescue Errno::ESRCH, Errno::ECHILD
      probe[:pid] = nil
      nil
    end

    # Finalizes a successful probe that has produced a result. Unlike terminate_probe,
    # this first waits for the helper to exit on its own before attempting termination.
    # This is the standard path for helpers that have finished their work and are
    # expected to exit promptly.
    def finalize_probe(probe, grace: helper_result_grace)
      pid = probe[:pid]
      probe[:reader]&.close unless probe[:reader]&.closed?
      return unless pid

      # Wait briefly for helper exit before clearing the PID.
      if probe_reaped_within_grace?(pid, grace: grace)
        probe[:pid] = nil
      else
        # Helper produced a result but is still running; escalate cleanup.
        terminate_probe(probe, grace: grace)
      end
    end

    def reap_probe(pid)
      return unless pid

      Process.wait(pid, Process::WNOHANG) || nil
    rescue Errno::ECHILD
      nil
    end

    def wait_for_probe_exit(pid, grace: helper_result_grace)
      return true if probe_reaped_within_grace?(pid, grace: grace)

      # Escalation: SIGKILL after grace period expired
      Process.kill('KILL', pid)
      wait_for_killed_probe_reap(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      true
    end

    def probe_reaped_within_grace?(pid, grace:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + grace

      loop do
        return true if reap_probe(pid)

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0

        sleep([helper_exit_poll_interval, remaining].min)
      end

      false
    end

    def wait_for_killed_probe_reap(pid)
      Process.wait(pid)
      true
    rescue Errno::ECHILD
      true
    end
  end
end
