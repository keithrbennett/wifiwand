# Set environment variable to enable faster timeouts during tests
ENV['RSPEC_RUNNING'] = 'true'

# Coverage reporting must be started before requiring any application code
require_relative 'support/coverage_config'
CoverageConfig.setup

require 'rspec'
require_relative '../lib/wifi-wand'
require_relative 'network_state_manager'
require_relative 'support/rspec_configuration'

$stdout.sync = true # Essential for test suite output to be in the correct order.

# Configure RSpec
RSpec.configure do |config|
  RSpecConfiguration.configure(config)
end