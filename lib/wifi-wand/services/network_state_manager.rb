# frozen_string_literal: true

require_relative '../timing_constants'

module WifiWand
  class NetworkStateManager
    RESTORE_CONNECT_RETRY_WAIT_SECONDS = 2.0
    RESTORE_CONNECT_RETRY_PATTERNS = [
      /Error:\s*-3900/i,
      /tmpErr/i,
      /couldn(?:\?\?\?|')t be completed/i,
    ].freeze

    EXPECTED_RESTORE_ERRORS = [
      WifiWand::Error,
      IOError,
      SocketError,
      Timeout::Error,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
    ].freeze

    def initialize(model, verbose: false, output: $stdout)
      @model = model
      @verbose = verbose
      @output = output
    end

    # Network State Management for Testing
    # These methods help capture and restore network state during disruptive tests

    def capture_network_state
      network_name = begin
        @model.connected_network_name
      rescue WifiWand::Error
        nil
      end

      # Always attempt to capture password for consistent restoration
      # If we're capturing network state, we should have the password available
      # for reliable restoration without repeated keychain prompts
      network_password = if network_name
        begin
          connected_network_password
        rescue WifiWand::Error => e
          @output.puts "Warning: Failed to retrieve password for #{network_name}: #{e.message}" if @verbose
          nil
        end
      end

      {
        wifi_enabled:     @model.wifi_on?,
        network_name:     network_name,
        network_password: network_password,
        interface:        @model.wifi_interface,
      }
    end

    def restore_network_state(state, fail_silently: false)
      @output.puts "restore_network_state: #{state} called" if @verbose
      return :no_state_to_restore unless state

      begin
        # Restore WiFi enabled state
        if state[:wifi_enabled]
          unless @model.wifi_on?
            @model.wifi_on
            @model.till(:wifi_on, timeout_in_secs: TimingConstants::WIFI_STATE_CHANGE_WAIT)
          end
        else
          if @model.wifi_on?
            @model.wifi_off
            @model.till(:wifi_off, timeout_in_secs: TimingConstants::WIFI_STATE_CHANGE_WAIT)
          end
          return # If WiFi should be off, we're done
        end

        # Restore network connection if one existed
        if state[:network_name] && state[:wifi_enabled]
          # If we are already connected to the original network, no need to proceed
          begin
            if @model.wifi_on? == state[:wifi_enabled] &&
                @model.connection_ready?(state[:network_name])
              return :already_connected
            end
          rescue WifiWand::Error => e
            if @verbose
              @output.puts "Warning: Unable to query current network (#{e.message}), " \
                'proceeding with connection attempt'
            end
          end

          password_to_use = state[:network_password]
          password_to_use = nil if password_to_use.respond_to?(:empty?) && password_to_use.empty?
          password_to_use ||= fallback_password_for(state[:network_name])

          begin
            connect_for_restore(state[:network_name], password_to_use)
            wait_for_connection_restoration(state[:network_name])
          rescue WifiWand::WaitTimeoutError => e
            begin
              actual_network = @model.connected_network_name
              if @verbose
                @output.puts "Warning: Connection timeout - expected #{state[:network_name].inspect}, " \
                  "currently connected to #{actual_network.inspect}"
              end
            rescue WifiWand::Error => name_error
              if @verbose
                @output.puts 'Warning: Connection timeout and failed to query current network: ' \
                  "#{name_error.message}"
              end
              actual_network = nil
            end

            reason = "timed out waiting for connection; currently connected to #{actual_network.inspect}"
            error = WifiWand::NetworkConnectionError.new(network_name: state[:network_name], reason: reason)
            error.set_backtrace(e.backtrace)
            raise error
          end
        end
      rescue *EXPECTED_RESTORE_ERRORS => e
        raise unless fail_silently

        @output&.puts "Warning: Could not restore network state (#{e.class}): #{e.message}"
        if state[:network_name] && @output
          @output.puts "You may need to manually reconnect to: #{state[:network_name]}"
        end
        nil
      end
    end

    private def connected_network_password
      network_name = begin
        @model.connected_network_name
      rescue WifiWand::Error
        nil
      end
      return nil unless network_name
      return nil unless connected_network_requires_password?

      @model.preferred_network_password(network_name, timeout_in_secs: nil)
    end

    private def connected_network_requires_password?
      security_type = @model.connection_security_type
      %w[WPA WPA2 WPA3 WEP].include?(security_type)
    rescue WifiWand::Error
      true
    end

    private def fallback_password_for(network_name)
      return nil unless network_name

      @model.preferred_network_password(network_name)
    rescue WifiWand::Error => e
      if @verbose
        @output.puts "Warning: Failed to retrieve fallback password for #{network_name}: " \
          "#{e.message}"
      end
      nil
    end

    private def connect_for_restore(network_name, password)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
        TimingConstants::NETWORK_CONNECTION_WAIT
      attempts = 0

      begin
        attempts += 1
        @model.connect(network_name, password)
      rescue WifiWand::CommandExecutor::OsCommandError => e
        raise unless retry_restore_connect?(e, deadline)

        if @verbose
          @output.puts "Warning: Restore connection attempt #{attempts} failed with a transient " \
            "networksetup error; retrying after #{RESTORE_CONNECT_RETRY_WAIT_SECONDS} seconds"
        end

        sleep(RESTORE_CONNECT_RETRY_WAIT_SECONDS)
        retry
      end
    end

    private def retry_restore_connect?(error, deadline)
      return false unless @model.respond_to?(:mac?) && @model.mac?
      return false unless error.command.to_s == 'networksetup'
      return false unless RESTORE_CONNECT_RETRY_PATTERNS.any? { |pattern| pattern.match?(error.text.to_s) }

      Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end

    private def wait_for_connection_restoration(network_name)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
        TimingConstants::NETWORK_CONNECTION_WAIT

      loop do
        return if @model.connection_ready?(network_name)

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise(WifiWand::WaitTimeoutError.new(
            action:  :associated,
            timeout: TimingConstants::NETWORK_CONNECTION_WAIT
          ))
        end

        sleep(TimingConstants::DEFAULT_WAIT_INTERVAL)
      end
    end
  end
end
