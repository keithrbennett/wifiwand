module WifiWand
  class StatusWaiter
    
    def initialize(model, verbose: false)
      @model = model
      @verbose = verbose
    end

    # Waits for the Internet connection to be in the desired state.
    # @param target_status must be in [:conn, :disc, :off, :on]; waits for that state
    # @param wait_interval_in_secs sleeps this interval between retries; if nil or absent,
    #        a default will be provided
    def wait_for(target_status, wait_interval_in_secs = nil)
      # One might ask, why not just put the 0.5 up there as the default argument.
      # We could do that, but we'd still need the line below in case nil
      # was explicitly specified. The default argument of nil above emphasizes that
      # the absence of an argument and a specification of nil will behave identically.
      wait_interval_in_secs ||= 0.5

      if @verbose
        puts "StatusWaiter: waiting for #{target_status}, interval (seconds): #{wait_interval_in_secs}"
      end

      finished_predicates = {
          conn: -> { @model.connected_to_internet? },
          disc: -> { ! @model.connected_to_internet? },
          on:   -> { @model.wifi_on? },
          off:  -> { ! @model.wifi_on? }
      }

      finished_predicate = finished_predicates[target_status]

      if finished_predicate.nil?
        raise ArgumentError.new(
            "Option must be one of #{finished_predicates.keys.inspect}. Was: #{target_status.inspect}")
      end

      if finished_predicate.()
        puts "StatusWaiter: completed without needing to wait" if @verbose
        return nil
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      until finished_predicate.()
        sleep(wait_interval_in_secs)
        puts("StatusWaiter: waiting #{wait_interval_in_secs} seconds for #{target_status}: #{Time.now}")
      end

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @verbose
        puts "StatusWaiter: #{target_status} wait time (seconds): #{end_time - start_time}"
      end
      nil
    end
  end
end