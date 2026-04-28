# frozen_string_literal: true

# Coverage reporting must be started before requiring any application code
require_relative 'support/coverage_config'
CoverageConfig.setup

require 'rspec'
require_relative '../lib/wifi-wand'
require_relative 'support/network_state_manager'
require_relative 'support/rspec_configuration'
require_relative 'support/matchers'
require_relative 'support/command_result_helper'
require_relative 'support/shared_command_examples'
require_relative 'support/cli_shared_context'

# Override timing constants for fast test execution.
# Production code uses the real (longer) values; tests reassign them here
# at load time to keep specs fast without coupling production to ENV['RSPEC_RUNNING'].
original_verbose = $VERBOSE
$VERBOSE = nil
WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT       = 0.25
WifiWand::TimingConstants::DNS_RESOLUTION_TIMEOUT       = 0.25
WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT = 1.0
WifiWand::TimingConstants::HTTP_CONNECTIVITY_TIMEOUT    = 0.25
require_relative '../lib/wifi-wand/mac_helper/mac_os_wifi_auth_helper'
WifiWand::MacOsWifiAuthHelper::HELPER_COMMAND_TIMEOUT_SECONDS  = 1.0
WifiWand::MacOsWifiAuthHelper::HELPER_TERMINATION_WAIT_SECONDS = 0.1
WifiWand::MacOsWifiAuthHelper::Client::HELPER_COMMAND_TIMEOUT_SECONDS = 1.0
$VERBOSE = original_verbose

$stdout.sync = true # Essential for test suite output to be in the correct order.

# Configure RSpec
RSpec.configure do |config|
  RSpecConfiguration.configure(config)
end
