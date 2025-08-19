require_relative '../timing_constants'

module WifiWand
  class NetworkStateManager
    
    def initialize(model, verbose: false)
      @model = model
      @verbose = verbose
    end

    # Network State Management for Testing
    # These methods help capture and restore network state during disruptive tests
    
    def capture_network_state
      {
        wifi_enabled: @model.wifi_on?,
        network_name: @model.connected_network_name,
        network_password: connected_network_password,
        interface: @model.wifi_interface
      }
    end
    
    def restore_network_state(state, fail_silently: false)
      puts "restore_network_state: #{state} called" if @verbose
      return :no_state_to_restore unless state
      
      begin
        # Restore wifi enabled state
        if state[:wifi_enabled]
          unless @model.wifi_on?
            @model.wifi_on
            @model.till :on, TimingConstants::WIFI_STATE_CHANGE_WAIT
          end
        else
          if @model.wifi_on?
            @model.wifi_off
            @model.till :off, TimingConstants::WIFI_STATE_CHANGE_WAIT
          end
          return # If wifi should be off, we're done
        end
        
        # Restore network connection if one existed
        if state[:network_name] && state[:wifi_enabled]
          # If we are already connected to the original network, no need to proceed
          return :already_connected if @model.wifi_on? == state[:wifi_enabled] && @model.connected_network_name == state[:network_name]

          # Try to reconnect with saved password or current password
          password = state[:network_password] || @model.preferred_network_password(state[:network_name])
          @model.connect(state[:network_name], password)
          @model.till :conn, TimingConstants::NETWORK_CONNECTION_WAIT
        end
      rescue => e
        if fail_silently
          $stderr.puts "Warning: Could not restore network state: #{e.message}"
          $stderr.puts "You may need to manually reconnect to: #{state[:network_name]}" if state[:network_name]
        else
          raise
        end
      end
    end
    
    private
    
    def connected_network_password
      return nil unless @model.connected_network_name
      @model.preferred_network_password(@model.connected_network_name)
    end
  end
end