# frozen_string_literal: true

require_relative '../timing_constants'

module WifiWand
  class NetworkStateManager
    def initialize(model, verbose: false, output: $stdout)
      @model = model
      @verbose = verbose
      @output = output
    end

    # Network State Management for Testing
    # These methods help capture and restore network state during disruptive tests

    def capture_network_state
      network_name = @model.connected_network_name

      # Always attempt to capture password for consistent restoration
      # If we're capturing network state, we should have the password available
      # for reliable restoration without repeated keychain prompts
      network_password = if network_name
        begin
          connected_network_password
        rescue => e
          @output.puts "Warning: Failed to retrieve password for #{network_name}: #{e.message}" if @verbose
          nil
        end
      end

      {
        wifi_enabled: @model.wifi_on?,
        network_name: network_name,
        network_password: network_password,
        interface: @model.wifi_interface
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
            @model.till(:on, timeout_in_secs: TimingConstants::WIFI_STATE_CHANGE_WAIT)
          end
        else
          if @model.wifi_on?
            @model.wifi_off
            @model.till(:off, timeout_in_secs: TimingConstants::WIFI_STATE_CHANGE_WAIT)
          end
          return # If WiFi should be off, we're done
        end

        # Restore network connection if one existed
        if state[:network_name] && state[:wifi_enabled]
          # If we are already connected to the original network, no need to proceed
          begin
            current_network = @model.connected_network_name
            return :already_connected if @model.wifi_on? == state[:wifi_enabled] && current_network == state[:network_name]
          rescue => e
            # If we can't determine current network, proceed with connection attempt
            @output.puts "Warning: Unable to query current network (#{e.message}), proceeding with connection attempt" if @verbose
          end

          password_to_use = state[:network_password]
          password_to_use = nil if password_to_use.respond_to?(:empty?) && password_to_use.empty?
          password_to_use ||= fallback_password_for(state[:network_name])

          begin
            @model.connect(state[:network_name], password_to_use)
            @model.till(:conn, timeout_in_secs: TimingConstants::NETWORK_CONNECTION_WAIT)
          rescue WifiWand::WaitTimeoutError => e
            begin
              actual_network = @model.connected_network_name
              if @verbose
                @output.puts "Warning: Connection timeout - expected #{state[:network_name].inspect}, currently connected to #{actual_network.inspect}"
              end
            rescue => name_error
              @output.puts "Warning: Connection timeout and failed to query current network: #{name_error.message}" if @verbose
              actual_network = nil
            end

            error = WifiWand::NetworkConnectionError.new(state[:network_name], "timed out waiting for connection; currently connected to #{actual_network.inspect}")
            error.set_backtrace(e.backtrace)
            raise error
          end
        end
      rescue => e
        raise unless fail_silently

        warn "Warning: Could not restore network state: #{e.message}"
        warn "You may need to manually reconnect to: #{state[:network_name]}" if state[:network_name]
        nil
      end
    end

    private

    def connected_network_password
      return nil unless @model.connected_network_name

      @model.preferred_network_password(@model.connected_network_name)
    end

    def fallback_password_for(network_name)
      return nil unless network_name

      @model.preferred_network_password(network_name)
    rescue => e
      @output.puts "Warning: Failed to retrieve fallback password for #{network_name}: #{e.message}" if @verbose
      nil
    end
  end
end
