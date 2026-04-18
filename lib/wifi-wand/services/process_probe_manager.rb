# frozen_string_literal: true

module WifiWand
  module ProcessProbeManager
    def terminate_probes(probes)
      probes.each { |probe| terminate_probe(probe) }
    end

    def terminate_probe(probe)
      pid = probe[:pid]
      return unless pid

      Process.kill('TERM', pid)
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
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + self.class::HELPER_RESULT_GRACE

      loop do
        return if reap_probe(pid)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep(0.01)
      end

      Process.kill('KILL', pid)
      reap_probe(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end
