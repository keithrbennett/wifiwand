# frozen_string_literal: true

require_relative '../errors'

module WifiWand
  class ConnectionManager
    MAX_NETWORK_NAME_BYTES = 32
    # Exactly 64 hexadecimal characters is treated as a raw PSK.
    MAX_PASSWORD_LENGTH = 64
    # Non-raw passphrases must fit within 63 UTF-8 bytes.
    MAX_PASSPHRASE_LENGTH = 63
    RAW_PSK_PATTERN = /\A\h{64}\z/
    CONTROL_CHAR_PATTERN = /\p{Cntrl}/

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
    # IMPORTANT: This method returns once the SSID association is confirmed, NOT when
    # DNS or Internet connectivity are available. The OS may still be negotiating an
    # IP address or DNS at that point. To guarantee full connectivity after connecting,
    # follow with: model.till(:internet_on) or CLI: till internet_on [timeout_secs]
    #
    # Note: The @last_connection_used_saved_password flag is cleared at the start
    # of each connect attempt and only set to true if a saved password is successfully
    # used. If the connection fails, this flag may not accurately represent the
    # most recent connection attempt's state.
    def connect(network_name, password = nil, skip_saved_password_lookup: false)
      reset_connection_state

      network_name, password = normalize_inputs(network_name, password)
      validate_network_name(network_name)

      # If we're already connected to the desired network, no need to proceed
      return if already_connected?(network_name)

      password, used_saved_password = resolve_password(network_name, password, skip_saved_password_lookup)

      perform_connection(network_name, password)
      store_saved_password_usage(used_saved_password)
      verify_connection(network_name, password)

      nil
    end

    # Returns true if the last connection attempt used a saved password.
    # Note: This flag is reset at the start of each connect() call, so it only
    # reflects saved password usage if the most recent connect() call completed
    # successfully. Failed connections may leave this in an inconsistent state.
    def last_connection_used_saved_password? = !!@last_connection_used_saved_password

    private def reset_connection_state = @last_connection_used_saved_password = nil

    # Normalizes and validates connection inputs.
    #
    # Accepted input types:
    # - Network name: String or Symbol (required, max 32 UTF-8 bytes)
    # - Password: String, Symbol, or nil (optional WiFi credential. wifi-wand
    #   rejects malformed raw PSKs and overlong passphrases, but leaves
    #   network-specific credential rules to the OS-specific connection layer.)
    #
    # Symbols are converted to Strings, nil passwords are preserved, and control characters
    # are rejected to avoid sending malformed connection inputs.
    #
    # @param network_name [String, Symbol] SSID or network name to connect to.
    # @param password [String, Symbol, nil] Optional pre-shared key.
    # @raise [InvalidNetworkNameError] when the network name is missing or malformed.
    # @raise [InvalidNetworkPasswordError] when the password is not a String/Symbol,
    #   contains control characters, or is neither a valid passphrase nor raw PSK.
    # @return [Array(String, String,nil)] normalized `[network_name, password]`.
    private def normalize_inputs(network_name, password)
      normalized_network_name = normalize_scalar_input(
        value:                network_name,
        allow_nil:            false,
        field_label:          'Network name',
        error_class:          InvalidNetworkNameError,
        blank_message:        'Network name cannot be empty',
        control_char_message: 'Network name cannot contain control characters'
      )

      normalized_password = normalize_scalar_input(
        value:                password,
        allow_nil:            true,
        max_length:           MAX_PASSWORD_LENGTH,
        field_label:          'Password',
        error_class:          InvalidNetworkPasswordError,
        blank_message:        nil,
        control_char_message: 'Password cannot contain control characters'
      )

      validate_password(normalized_password)

      [normalized_network_name, normalized_password]
    end

    private def validate_network_name(network_name)
      if network_name.nil? || network_name.empty?
        raise(InvalidNetworkNameError.new(network_name: network_name || ''))
      end

      return if network_name.bytesize <= MAX_NETWORK_NAME_BYTES

      raise(InvalidNetworkNameError.new(
        network_name: network_name,
        reason:       "Network name cannot exceed #{MAX_NETWORK_NAME_BYTES} bytes"
      ))
    end

    private def validate_password(password)
      return if password.nil? || password.empty?
      return if password.match?(RAW_PSK_PATTERN)
      return if password.bytesize <= MAX_PASSPHRASE_LENGTH

      reason = if password.length == MAX_PASSWORD_LENGTH
        'Password must be 1-63 bytes, or exactly 64 hexadecimal characters'
      else
        'Password passphrases cannot exceed 63 bytes'
      end

      raise InvalidNetworkPasswordError, reason
    end

    private def already_connected?(network_name)
      active_connection_matches?(network_name)
    rescue WifiWand::Error
      false
    end

    # Determines the password to use for a connection attempt.
    #
    # Behavior:
    # - If a non-empty `password` is provided by the caller, it is used as-is and
    #   `used_saved_password` is false.
    # - If the caller provides an empty string (`''`), it is treated as an explicit
    #   request to skip saved credentials and attempt the connection without a
    #   password.
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
    private def resolve_password(network_name, password, skip_saved_password_lookup = false)
      return [password, false] if skip_saved_password_lookup

      if password == ''
        # Explicit request to connect without a password; bypass saved credentials
        return [nil, false]
      end

      password_provided = password && !password.empty?
      return [password, false] if password_provided

      begin
        preferred_network_exists = model.has_preferred_network?(network_name)
      rescue WifiWand::Error
        preferred_network_exists = false
      end

      if preferred_network_exists
        begin
          saved_password = model.preferred_network_password(network_name)
          unless saved_password.nil? || saved_password.empty?
            return [saved_password, true]
          end
        rescue WifiWand::Error
          # If we can't get the saved password, continue without one
          # This could happen due to keychain access issues, etc.
        end
      end

      [nil, false]
    end

    private def perform_connection(network_name, password)
      model.wifi_on
      model._connect(network_name, password)
      wait_for_connection_activation(network_name)
    end

    private def store_saved_password_usage(used_saved_password)
      @last_connection_used_saved_password = used_saved_password
    end

    private def verify_connection(network_name, _password)
      return if active_connection_matches?(network_name)

      actual_network_name = begin
        model.connected_network_name
      rescue WifiWand::Error
        nil
      end

      # Some platforms can report the SSID before higher-level readiness checks
      # settle. Treat an exact SSID match as a successful connection.
      return if actual_network_name == network_name

      error_detail = actual_network_name \
        ? "connected to '#{actual_network_name}' instead" \
        : 'unable to connect to any network'
      raise(NetworkConnectionError.new(network_name: network_name, reason: error_detail))
    end

    private def active_connection_matches?(network_name)
      model.connection_ready?(network_name)
    end

    private def wait_for_connection_activation(network_name)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        # Association is the first milestone: the radio joined the SSID, but the
        # OS may still be promoting the connection profile to "active".
        model.till(:associated, timeout_in_secs: WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT)
      rescue WifiWand::WaitTimeoutError
        # Fall through to explicit active-connection polling so verification can
        # distinguish "associated but not fully active" from a real failure.
      end

      loop do
        begin
          # Use the model's higher-level readiness check here rather than raw
          # association state so callers only proceed once DNS/IP/profile state
          # has settled enough for subsequent commands to be reliable.
          return if active_connection_matches?(network_name)
        rescue WifiWand::Error
          # NetworkManager can transiently report no active connection while
          # activation is still settling; keep polling until timeout.
        end

        elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        return if elapsed_time >= WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT

        sleep(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL)
      end
    end

    private def normalize_scalar_input(
      value:, allow_nil:, field_label:, error_class:, blank_message:, control_char_message:, max_length: nil
    )
      if value.nil?
        return nil if allow_nil

        reason = blank_message || "#{field_label} is required"
        raise build_validation_error(error_class, nil, reason)
      end

      unless value.is_a?(String) || value.is_a?(Symbol)
        raise build_validation_error(error_class, value, "#{field_label} must be a String or Symbol")
      end

      string_value = value.to_s

      if string_value.empty?
        if allow_nil
          return string_value
        elsif blank_message
          raise build_validation_error(error_class, string_value, blank_message)
        end
      end

      if max_length && string_value.length > max_length
        raise build_validation_error(
          error_class, string_value, "#{field_label} cannot exceed #{max_length} characters"
        )
      end

      if control_char_message && string_value.match?(CONTROL_CHAR_PATTERN)
        raise build_validation_error(error_class, string_value, control_char_message)
      end

      string_value
    end

    private def build_validation_error(error_class, value, reason)
      if error_class == InvalidNetworkPasswordError
        error_class.new(reason)
      else
        error_class.new(network_name: value, reason: reason)
      end
    end
  end
end
