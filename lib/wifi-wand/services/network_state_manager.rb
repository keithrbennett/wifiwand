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
        rescue
          nil
        end
      else
        nil
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
          return :already_connected if @model.wifi_on? == state[:wifi_enabled] && @model.connected_network_name == state[:network_name]

          password_to_use = state[:network_password]
          password_to_use = nil if password_to_use.respond_to?(:empty?) && password_to_use.empty?
          password_to_use ||= fallback_password_for(state[:network_name])

          begin
            @model.connect(state[:network_name], password_to_use)
            @model.till(:conn, timeout_in_secs: TimingConstants::NETWORK_CONNECTION_WAIT)
          rescue WifiWand::WaitTimeoutError => wait_error
            begin
              actual_network = @model.connected_network_name
            rescue
              actual_network = nil
            end

            error = WifiWand::NetworkConnectionError.new(state[:network_name], "timed out waiting for connection; currently connected to #{actual_network.inspect}")
            error.set_backtrace(wait_error.backtrace)
            raise error
          end
        end
      rescue => e
        raise unless fail_silently
        $stderr.puts "Warning: Could not restore network state: #{e.message}"
        $stderr.puts "You may need to manually reconnect to: #{state[:network_name]}" if state[:network_name]
        nil
      end
    end
    
    private

    def connected_network_password
      return nil unless @model.connected_network_name
      @model.preferred_network_password(@model.connected_network_name)
    end

    # Only attempt to fetch a password when interactive to avoid GUI keychain prompts
    # in non-interactive environments (e.g., RSpec/CI).
    def connected_network_password_if_safe
      begin
        return nil if macos_keychain_risky?
        connected_network_password
      rescue
        nil
      end
    end

    def interactive_session?
      $stdin.tty?
    end

    def macos_keychain_risky?
      # Only consider it risky (GUI prompt) when using the real macOS model without a TTY
      defined?(WifiWand::MacOsModel) && @model.is_a?(WifiWand::MacOsModel) && !interactive_session?
    end

    def avoid_keychain_for_model?
      return false unless defined?(WifiWand::MacOsModel) && @model.is_a?(WifiWand::MacOsModel)
      return false unless ENV['RSPEC_RUNNING'] == 'true'

      macos_keychain_risky?
    end

    def fallback_password_for(network_name)
      return nil unless network_name

      @model.preferred_network_password(network_name)
    rescue
      nil
    end
  end
end
