require 'rspec'
require 'ostruct'

# Require the main library
require_relative '../lib/wifi-wand'
require_relative '../lib/wifi-wand/operating_systems'
require_relative 'network_state_manager'

# Configure RSpec
RSpec.configure do |config|
  
  # Enable RSpec tags
  config.filter_run_including :focus => true
  config.run_all_when_everything_filtered = true
  
  # Exclude disruptive tests by default
  config.filter_run_excluding :disruptive => true
  
  # Auto-detect current OS and filter tests accordingly
  begin
    os_detector = WifiWand::OperatingSystems.new
    current_os = os_detector.current_os
    current_os_name = current_os.class.name.split('::').last.gsub('Os', '').downcase.to_sym
    compatible_os_tag = "os_#{current_os_name}".to_sym
    
    # Filter tests based on OS compatibility (evaluated once per run)
    # Only filter if command line doesn't specify any tag inclusion/exclusion
    if config.inclusion_filter.rules.empty? && config.exclusion_filter.rules.empty?
      config.filter_run do |metadata|
        # Apply default exclusion for disruptive tests
        return false if metadata[:disruptive]
        
        # Check OS compatibility for non-disruptive tests
        os_tags = metadata.keys.select { |key| key.to_s.start_with?('os_') }
        
        if os_tags.empty?
          true # No OS tags - run on all OSes (common tests)
        else
          # Test has OS tags - only run if compatible with current OS
          os_tags.include?(compatible_os_tag)
        end
      end
    end
    
  rescue => e
    puts "Warning: Could not detect current OS for test filtering: #{e.message}"
    puts "Running all tests - some may fail due to OS incompatibility"
  end
  
  # Add custom tags
  config.define_derived_metadata do |meta|
    meta[:slow] = true if meta[:disruptive]
  end
  
  # Example usage documentation
  config.before(:suite) do
    puts "\n" + "="*60
    puts "TEST FILTERING OPTIONS:"
    puts "="*60
    puts "Run only read-only tests (default):"
    puts "  bundle exec rspec"
    puts ""
    puts "Run read-only + disruptive tests:"
    puts "  bundle exec rspec --tag disruptive"
    puts ""
    puts "Run ALL tests (including disruptive):"
    puts "  bundle exec rspec --tag ~disruptive"
    puts ""
    puts "Run specific file with all tests:"
    puts "  bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb --tag disruptive"
    puts ""
    puts "="*60 + "\n"
  end
  
  # Network State Management for disruptive tests
  config.before(:suite) do
    NetworkStateManager.capture_state
  end
  
  # Helper method for individual tests to restore network state
  config.include(Module.new do
    def restore_network_state
      NetworkStateManager.restore_state
    end
    
    def network_state
      NetworkStateManager.network_state
    end
  end)
  
  # Restore network state after each disruptive test
  config.after(:each, :disruptive) do
    NetworkStateManager.restore_state
  end
  
  # Attempt final restoration at the end of test suite
  config.after(:suite) do
    network_state = NetworkStateManager.network_state
    if network_state && network_state[:network_name]
      puts "\n" + "="*60
      begin
        NetworkStateManager.restore_state
        puts "✅ Successfully restored network connection: #{network_state[:network_name]}"
      rescue => e
        puts "⚠️  Could not restore network connection: #{e.message}"
        puts "You may need to manually reconnect to: #{network_state[:network_name]}"
      end
      puts "="*60
    end
  end
  
end