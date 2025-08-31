module WifiWand
  module TimingConstants
    # Default wait intervals for status polling
    DEFAULT_WAIT_INTERVAL = 0.5

    # StatusWaiter timeouts
    STATUS_WAIT_TIMEOUT_LONG = 15
    STATUS_WAIT_TIMEOUT_SHORT = 5
    
    # NetworkStateManager wait intervals
    WIFI_STATE_CHANGE_WAIT = 0.05  # Wait for WiFi on/off state changes
    NETWORK_CONNECTION_WAIT = 0.25  # Wait for network connection establishment
    
    # NetworkConnectivityTester timeouts
    TCP_CONNECTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.1 : 2      # Individual TCP connection timeout
    DNS_RESOLUTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.1 : 2      # Individual DNS resolution timeout  
    OVERALL_CONNECTIVITY_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.2 : 2.5  # Overall timeout for all attempts
    
    # Test intervals (used in specs)
    FAST_TEST_INTERVAL = 0.1        # Quick interval for tests
  end
end