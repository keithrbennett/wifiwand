# frozen_string_literal: true

module WifiWand
  # Base error class - keep for backward compatibility
  class Error < RuntimeError; end

  # === NETWORK CONNECTION ERRORS ===
  class NetworkNotFoundError < Error
    attr_reader :network_name, :available_networks

    def initialize(network_name, available_networks = [])
      @network_name = network_name
      @available_networks = available_networks
      super(build_message)
    end

    private

    def build_message
      msg = "Network '#{network_name}' not found"
      msg += if available_networks.any?
        ". Available networks: #{available_networks.join(', ')}"
      else
        '. No networks are currently available'
      end
      msg
    end
  end

  class NetworkConnectionError < Error
    attr_reader :network_name, :reason

    def initialize(network_name, reason = nil)
      @network_name = network_name
      @reason = reason
      msg = "Failed to connect to network '#{network_name}'"
      msg += ": #{reason}" if reason
      super(msg)
    end
  end

  class NetworkAuthenticationError < Error
    attr_reader :network_name, :reason

    def initialize(network_name, reason = nil)
      @network_name = network_name
      @reason = reason
      msg = "Authentication failed for network '#{network_name}'"
      msg += ": #{reason}" if reason
      msg += '. Please verify the password is correct' unless reason&.include?('password')
      super(msg)
    end
  end


  # === WIFI HARDWARE ERRORS ===

  class WifiInterfaceError < Error
    def initialize(interface = nil)
      msg = interface ? "WiFi interface '#{interface}' not found" : 'No WiFi interface found'
      msg += '. Ensure WiFi hardware is present and drivers are installed'
      super(msg)
    end
  end

  class WifiEnableError < Error
    def initialize
      super('WiFi could not be enabled. Check hardware and permissions')
    end
  end

  class WifiDisableError < Error
    def initialize
      super('WiFi could not be disabled. Check permissions')
    end
  end

  class WaitTimeoutError < Error
    def initialize(action, timeout)
      super("Timed out after #{timeout} seconds waiting for #{action}")
    end
  end

  # === CONFIGURATION ERRORS ===
  class InvalidIPAddressError < Error
    attr_reader :invalid_addresses

    def initialize(invalid_addresses)
      @invalid_addresses = Array(invalid_addresses)
      super("Invalid IP address(es): #{@invalid_addresses.join(', ')}")
    end
  end

  class InvalidNetworkNameError < Error
    attr_reader :network_name, :reason

    def initialize(network_name, reason = 'Network name cannot be empty')
      @network_name = network_name
      @reason = reason
      display_name = network_name.to_s
      super("Invalid network name: '#{display_name}'. #{reason}")
    end
  end

  class InvalidNetworkPasswordError < Error
    attr_reader :reason

    def initialize(_password = nil, reason = 'Password is invalid')
      @reason = reason
      super("Invalid network password: #{reason}")
    end
  end

  class InvalidInterfaceError < Error
    def initialize(interface)
      super("'#{interface}' is not a valid WiFi interface")
    end
  end

  # === SYSTEM/PERMISSION ERRORS ===
  class CommandNotFoundError < Error
    def initialize(commands)
      commands = Array(commands)
      super("Missing required system command(s): #{commands.join(', ')}")
    end
  end

  # === MACOS-SPECIFIC ERRORS ===
  class KeychainAccessDeniedError < Error
    def initialize(network_name)
      super("Keychain access denied for network '#{network_name}'. Please grant access when prompted")
    end
  end

  class KeychainAccessCancelledError < Error
    def initialize(network_name)
      super("Keychain access cancelled for network '#{network_name}'")
    end
  end

  class KeychainNonInteractiveError < Error
    def initialize(network_name)
      super("Cannot access keychain for network '#{network_name}' in non-interactive environment")
    end
  end

  class KeychainError < Error
    def initialize(message)
      super
    end
  end

  # === OPERATING SYSTEM DETECTION ERRORS ===
  class MultipleOSMatchError < Error
    def initialize(matching_os_names)
      super("Multiple OS matches found: #{matching_os_names.join(', ')}. This should not happen")
    end
  end

  class NoSupportedOSError < Error
    def initialize
      super('No supported operating system detected. WifiWand supports macOS and Ubuntu Linux')
    end
  end

  class PreferredNetworkNotFoundError < Error
    def initialize(network_name)
      super("Network '#{network_name}' not in preferred networks list")
    end
  end

  class ConfigurationError < Error
    def initialize(message)
      super
    end
  end

  # === EXTERNAL SERVICE ERRORS ===
  class PublicIPLookupError < Error
    attr_reader :status_code, :status_message

    def initialize(status_code = nil, status_message = nil)
      @status_code = status_code
      @status_message = status_message
      message = if status_code
        "HTTP error fetching public IP info: #{status_code} #{status_message}"
      else
        'Public IP lookup failed'
      end
      super(message)
    end
  end

  # === COMMAND LINE INTERFACE ERRORS ===
  class BadCommandError < Error
    def initialize(error_message)
      super
    end
  end
end
