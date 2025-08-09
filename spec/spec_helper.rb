require 'rspec'
require 'ostruct'

# Require the main library
require_relative '../lib/wifi-wand'

# Configure RSpec
RSpec.configure do |config|
  
  # Enable RSpec tags
  config.filter_run_including :focus => true
  config.run_all_when_everything_filtered = true
  
  # Exclude high-risk tags by default
  config.filter_run_excluding :network_connection => true
  config.filter_run_excluding :modifies_system => true
  
  # Add custom tags
  config.define_derived_metadata do |meta|
    meta[:slow] = true if meta[:modifies_system] || meta[:network_connection]
  end
  
  # Example usage documentation
  config.before(:suite) do
    puts "\n" + "="*60
    puts "TEST FILTERING OPTIONS:"
    puts "="*60
    puts "Run only read-only tests (default):"
    puts "  bundle exec rspec"
    puts ""
    puts "Run read-only + system-modifying tests:"
    puts "  bundle exec rspec --tag ~network_connection"
    puts "  OR"
    puts "  bundle exec rspec --tag modifies_system"
    puts ""
    puts "Run ALL tests (including network connections):"
    puts "  bundle exec rspec --tag network_connection"
    puts "  OR"
    puts "  bundle exec rspec --tag ~no_network"
    puts ""
    puts "Run specific file with all tests:"
    puts "  bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb --tag ~network_connection"
    puts ""
    puts "="*60 + "\n"
  end
  
  # Store original wifi state for system-modifying tests
  config.before(:context, :modifies_system) do
    @original_wifi_state = nil
  end
  
  # Cleanup after system-modifying tests
  config.after(:context, :modifies_system) do
    # We don't restore wifi state automatically as it might disrupt user workflow
    puts "\nNote: Some tests may have modified your system's wifi state."
  end
  
end