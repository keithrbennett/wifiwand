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
    # tolerating async cleanup; production needs 2s to cover high-latency uplinks.
    TCP_CONNECTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.25 : 2
    # Same reasoning as above: short for mocked DNS, 2s for off-network scenarios.
    DNS_RESOLUTION_TIMEOUT = ENV['RSPEC_RUNNING'] ? 0.25 : 2
    # The overall window is wider because we allow one retry cycle. Tests finish
    # quickly with 1s; production gets 2.5s to cover TCP + DNS + retry overhead.
    OVERALL_CONNECTIVITY_TIMEOUT = ENV['RSPEC_RUNNING'] ? 1.0 : 2.5
    
    # Spec helper interval for rapid polling in deterministic unit tests.
    FAST_TEST_INTERVAL = 0.1
  end
end
