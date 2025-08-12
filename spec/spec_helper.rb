require 'rspec'
require 'ostruct'

# Require the main library
require_relative '../lib/wifi-wand'
require_relative '../lib/wifi-wand/operating_systems'

# Configure RSpec
RSpec.configure do |config|
  
  # Enable RSpec tags
  config.filter_run_including :focus => true
  config.run_all_when_everything_filtered = true
  
  # Exclude high-risk tags by default
  config.filter_run_excluding :network_connection => true
  config.filter_run_excluding :modifies_system => true
  
  # Auto-detect current OS and filter tests accordingly
  begin
    os_detector = WifiWand::OperatingSystems.new
    current_os = os_detector.current_os
    current_os_name = current_os.class.name.split('::').last.gsub('Os', '').downcase.to_sym
    compatible_os_tag = "os_#{current_os_name}".to_sym
    
    # Filter tests based on OS compatibility (evaluated once per run)
    config.filter_run do |metadata|
      # If test has no OS tags, run it unconditionally
      os_tags = metadata.keys.select { |key| key.to_s.start_with?('os_') }
      
      if os_tags.empty?
        true # No OS tags - run on all OSes (common tests)
      else
        # Test has OS tags - only run if compatible with current OS
        os_tags.include?(compatible_os_tag)
      end
    end
    
  rescue => e
    puts "Warning: Could not detect current OS for test filtering: #{e.message}"
    puts "Running all tests - some may fail due to OS incompatibility"
  end
  
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