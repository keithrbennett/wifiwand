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
      if available_networks.any?
        msg += ". Available networks: #{available_networks.join(', ')}"
      else
        msg += ". No networks are currently available"
      end
      msg
    end
  end
  
  class NetworkConnectionError < Error
    def initialize(network_name, reason = nil)
      msg = "Failed to connect to network '#{network_name}'"
      msg += ": #{reason}" if reason
      super(msg)
    end
  end
  

  # === WIFI HARDWARE ERRORS ===
  
  class WifiInterfaceError < Error
    def initialize(interface = nil)
      msg = interface ? "WiFi interface '#{interface}' not found" : "No WiFi interface found"
      msg += ". Ensure WiFi hardware is present and drivers are installed"
      super(msg)
    end
  end
  
  class WifiEnableError < Error
    def initialize
      super("WiFi could not be enabled. Check hardware and permissions")
    end
  end
  
  class WifiDisableError < Error
    def initialize
      super("WiFi could not be disabled. Check permissions")
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
    def initialize(network_name)
      super("Invalid network name: '#{network_name}'. Network name cannot be empty")
    end
  end
  
  class InvalidInterfaceError < Error
    def initialize(interface)
      super("'#{interface}' is not a valid WiFi interface")
    end
  end

  # === SYSTEM/PERMISSION ERRORS ===
  class UnsupportedSystemError < Error
    def initialize(required_version = nil, current_version = nil)
      msg = "Unsupported system"
      if required_version && current_version
        msg += ". Requires #{required_version} or later, found #{current_version}"
      end
      super(msg)
    end
  end
  
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


  # === OPERATING SYSTEM DETECTION ERRORS ===
  class MultipleOSMatchError < Error
    def initialize(matching_os_names)
      super("Multiple OS matches found: #{matching_os_names.join(', ')}. This should not happen")
    end
  end
  
  class NoSupportedOSError < Error
    def initialize
      super("No supported operating system detected. WifiWand supports macOS and Ubuntu Linux")
    end
  end

  class PreferredNetworkNotFoundError < Error
    def initialize(network_name)
      super("Network '#{network_name}' not in preferred networks list")
    end
  end
end