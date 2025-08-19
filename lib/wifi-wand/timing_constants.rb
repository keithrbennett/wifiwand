module WifiWand
  module TimingConstants
    # Default wait intervals for status polling
    DEFAULT_WAIT_INTERVAL = 0.5
    
    # NetworkStateManager wait intervals
    WIFI_STATE_CHANGE_WAIT = 0.05  # Wait for wifi on/off state changes
    NETWORK_CONNECTION_WAIT = 0.25  # Wait for network connection establishment
    
    # NetworkConnectivityTester timeouts
    TCP_CONNECTION_TIMEOUT = 2      # Individual TCP connection timeout
    DNS_RESOLUTION_TIMEOUT = 2      # Individual DNS resolution timeout  
    OVERALL_CONNECTIVITY_TIMEOUT = 2.5  # Overall timeout for all attempts
    
    # Test intervals (used in specs)
    FAST_TEST_INTERVAL = 0.1        # Quick interval for tests
  end
end