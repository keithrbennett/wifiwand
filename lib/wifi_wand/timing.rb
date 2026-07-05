# frozen_string_literal: true

module WifiWand
  module Timing
    def status_deadline(timeout_in_secs)
      monotonic_now + timeout_in_secs if timeout_in_secs
    end

    def status_timeout_for(deadline)
      return nil unless deadline

      [deadline - monotonic_now, 0].max
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # module_function makes these callable as WifiWand::Timing.foo (module methods)
    # and also mixes them into includers as *private* instance methods. External
    # callers on an includer's instance will hit NoMethodError; use the module
    # form (e.g. WifiWand::Timing.monotonic_now) for outside access.
    module_function :status_deadline, :status_timeout_for, :monotonic_now
  end
end
