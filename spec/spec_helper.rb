# frozen_string_literal: true

# Coverage reporting must be started before requiring any application code
require_relative 'support/coverage_config'
CoverageConfig.setup

require 'rspec'
require_relative '../lib/wifi_wand'
require_relative 'support/network_state_manager'
require_relative 'support/rspec_configuration'
require_relative 'support/matchers'
require_relative 'support/command_result_helper'
require_relative 'support/shared_command_examples'
require_relative 'support/cli_shared_context'

$stdout.sync = true # Essential for test suite output to be in the correct order.

# Configure RSpec
RSpec.configure do |config|
  RSpecConfiguration.configure(config)
end
