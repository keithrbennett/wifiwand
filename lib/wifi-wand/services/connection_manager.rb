# frozen_string_literal: true

require_relative '../errors'

module WifiWand
  
class ConnectionManager
  
  attr_reader :model, :verbose_mode
  
  def initialize(model, verbose: false)
    @model = model
    @verbose_mode = verbose
    @last_connection_used_saved_password = nil
  end
  
  # Connects to the passed network name, optionally with password.
  # Turns WiFi on first, in case it was turned off.
  # Relies on model implementation of _connect().
  #
  # Note: The @last_connection_used_saved_password flag is cleared at the start 
  # of each connect attempt and only set to true if a saved password is successfully 
  # used. If the connection fails, this flag may not accurately represent the 
  # most recent connection attempt's state.
  def connect(network_name, password = nil)
    reset_connection_state
    
    network_name, password = normalize_inputs(network_name, password)
    validate_network_name(network_name)
    
    # If we're already connected to the desired network, no need to proceed
    return if already_connected?(network_name)
    
    password, used_saved_password = resolve_password(network_name, password)
    
    perform_connection(network_name, password)
    store_saved_password_usage(used_saved_password)
    verify_connection(network_name, password)
    
    nil
  end
  
  # Returns true if the last connection attempt used a saved password.
  # Note: This flag is reset at the start of each connect() call, so it only
  # reflects saved password usage if the most recent connect() call completed
  # successfully. Failed connections may leave this in an inconsistent state.
  def last_connection_used_saved_password?
    !!@last_connection_used_saved_password
  end
  
  private
  
  def reset_connection_state
    @last_connection_used_saved_password = nil
  end
  
  def normalize_inputs(network_name, password)
    # Allow symbols and anything responding to to_s for user convenience
    [network_name&.to_s, password&.to_s]
  end
  
  def validate_network_name(network_name)
    if network_name.nil? || network_name.empty?
      raise InvalidNetworkNameError.new(network_name || "")
    end
  end
  
  def already_connected?(network_name)
    network_name == model.connected_network_name
  end
  
  # Determines the password to use for a connection attempt.
  #
  # Behavior:
  # - If a non-empty `password` is provided by the caller, it is used as-is and
  #   `used_saved_password` is false.
  # - Otherwise, when `network_name` is present in the model's preferred networks,
  #   the method attempts to fetch a saved password via
  #   `model.preferred_network_password(network_name)`. If a non-empty saved
  #   password is found, it is returned and `used_saved_password` is true.
  # - Failures while reading preferred networks or retrieving the saved password
  #   are treated as non-fatal: they are rescued and the method falls back to
  #   returning `[nil, false]`.
  #
  # @param network_name [String] The SSID to connect to (already normalized).
  # @param password [String, nil] Optional user-provided password; when present,
  #   it takes precedence over any saved password.
  # @return [Array<(String,nil), Boolean>] A two-element array of
  #   `[resolved_password, used_saved_password]`, where `resolved_password` may be
  #   nil when no password could be determined.
  def resolve_password(network_name, password)
    password_provided = password && password.length > 0
    return [password, false] if password_provided

    begin
      preferred = model.preferred_networks
    rescue
      preferred = []
    end

    if preferred.include?(network_name)
      begin
        saved_password = model.preferred_network_password(network_name)
        unless saved_password.nil? || saved_password.empty?
          return [saved_password, true]
        end
      rescue
        # If we can't get the saved password, continue without one
        # This could happen due to keychain access issues, etc.
      end
    end

    [nil, false]
  end
  
  def perform_connection(network_name, password)
    model.wifi_on
    model._connect(network_name, password)
    begin
      model.till(:conn, timeout_in_secs: WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT)
    rescue WifiWand::WaitTimeoutError
      # Allow verification step to decide success/failure based on actual state
    end
  end
  
  def store_saved_password_usage(used_saved_password)
    @last_connection_used_saved_password = used_saved_password
  end
  
  def verify_connection(network_name, password)
    actual_network_name = model.connected_network_name
    
    unless actual_network_name == network_name
      error_detail = actual_network_name ? "connected to '#{actual_network_name}' instead" : "unable to connect to any network"
      raise NetworkConnectionError.new(network_name, error_detail)
    end
  end
end
end
