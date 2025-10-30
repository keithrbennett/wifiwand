# frozen_string_literal: true

module WifiWand
  module TimingConstants
    # Poll hardware state twice a second to balance responsiveness with CPU usage.
    DEFAULT_WAIT_INTERVAL = 0.5

    # Allow up to 15 seconds when we expect a full association cycle
    # (driver load + authentication + DHCP) before declaring failure.
    STATUS_WAIT_TIMEOUT_LONG = 15
    # Use a shorter window for quick retries such as rapid on/off toggles.
    STATUS_WAIT_TIMEOUT_SHORT = 5
    
    # Many Realtek/Broadcom chipsets need multiple seconds to report link-up/-down.
    # Value was 0.05s originally but was raised to 5s after repeated flake reports.
    WIFI_STATE_CHANGE_WAIT = 5.0
    # Wait long enough for DHCP + captive portal redirects before the next poll.
    NETWORK_CONNECTION_WAIT = 10.0 
    
    # NetworkConnectivityTester timeouts
    # Integration tests stub out sockets, so 0.25s keeps specs fast while still
    # tolerating async cleanup; production needs longer timeouts to avoid flaky results
    # on slow or degraded networks. Increased from 2s to 5s after observing intermittent
    # internet on/off events during logging, which indicates connectivity checks were
    # timing out due to network latency rather than actual connectivity loss.
    TCP_CONNECTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.25 : 5
    # Same reasoning as above: short for mocked DNS, 5s for slow DNS servers or high latency.
    DNS_RESOLUTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.25 : 5
    # The overall window is wider to accommodate both TCP and DNS checks with retries.
    # Tests finish quickly with 1s; production gets 6s to cover TCP + DNS + latency.
    OVERALL_CONNECTIVITY_TIMEOUT = ENV['RSPEC_RUNNING'] ? 1.0 : 6
    
    # Spec helper interval for rapid polling in deterministic unit tests.
    FAST_TEST_INTERVAL = 0.1

    # Default polling interval for event logging (in seconds)
    EVENT_LOG_POLLING_INTERVAL = 5

    # Fast connectivity check timeout for log command (in seconds)
    # Short timeout optimized for continuous monitoring where speed matters
    FAST_CONNECTIVITY_TIMEOUT = 1.0
    # Individual TCP connection timeout for fast checks
    FAST_TCP_CONNECTION_TIMEOUT = 0.8
  end
end
