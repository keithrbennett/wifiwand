require_relative '../timing_constants'

module WifiWand
  class StatusWaiter
    
    def initialize(model, verbose: false)
      @model = model
      @verbose = verbose
    end

    # Waits for the Internet connection to be in the desired state.
    # @param target_status must be in [:conn, :disc, :off, :on]; waits for that state
    # @param timeout_in_secs after this many seconds, the method will raise a WaitTimeoutError;
    #        if nil (default), waits indefinitely
    # @param wait_interval_in_secs sleeps this interval between retries; if nil or absent,
    #        a default will be provided
    def wait_for(target_status, timeout_in_secs = nil, wait_interval_in_secs = nil)
      wait_interval_in_secs ||= TimingConstants::DEFAULT_WAIT_INTERVAL
      message_prefix = "StatusWaiter (#{target_status}):"

      if @verbose
        timeout_display = timeout_in_secs ? "#{timeout_in_secs}s" : "never"
        puts "#{message_prefix} starting, timeout: #{timeout_display}, interval: #{wait_interval_in_secs}s"
      end

      finished_predicates = {
          conn: -> { @model.connected_to_internet? },
          disc: -> { !@model.connected_to_internet? },
          on:   -> { @model.wifi_on? },
          off:  -> { !@model.wifi_on? }
      }

      finished_predicate = finished_predicates[target_status]

      if finished_predicate.nil?
        raise ArgumentError, "Option must be one of #{finished_predicates.keys.inspect}. Was: #{target_status.inspect}"
      end

      if finished_predicate.call
        puts "#{message_prefix} completed without needing to wait" if @verbose
        return nil
      else
        puts "#{message_prefix} First attempt failed, entering waiting loop" if @verbose
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        if timeout_in_secs && elapsed_time >= timeout_in_secs
          raise WaitTimeoutError.new(target_status, timeout_in_secs)
        end

        puts "#{message_prefix} checking predicate..." if @verbose
        if finished_predicate.call
          if @verbose
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            puts "#{message_prefix} wait time (seconds): #{end_time - start_time}"
          end
          return nil
        end
        sleep(wait_interval_in_secs)
      end
    end
  end
end