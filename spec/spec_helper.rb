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
  
  # Auto-detect current OS and filter tests accordingly
  begin
    os_detector = WifiWand::OperatingSystems.new
    current_os = os_detector.current_os
    current_os_name = current_os.class.name.split('::').last.gsub('Os', '').downcase.to_sym
    compatible_os_tag = "os_#{current_os_name}".to_sym
    
    # Store in global variable for use in before hooks
    $compatible_os_tag = compatible_os_tag
    
    # Apply default exclusion for disruptive tests unless user wants all tests
    # Use RSPEC_DISABLE_EXCLUSIONS=true to run ALL tests including disruptive ones
    unless ENV['RSPEC_DISABLE_EXCLUSIONS'] == 'true'
      config.filter_run_excluding :disruptive => true
    end
    
  rescue => e
    puts "Warning: Could not detect current OS for test filtering: #{e.message}"
    puts "Running all tests - some may fail due to OS incompatibility"
  end
  
  # Skip OS-incompatible tests before they run
  config.before(:each) do |example|
    # Skip OS-incompatible tests
    os_tags = example.metadata.keys.select { |key| key.to_s.start_with?('os_') }
    if os_tags.any? && !os_tags.include?($compatible_os_tag)
      skip "Skipping #{os_tags.inspect} tests on current OS (#{$compatible_os_tag})"
    end
  end
  
  # Add custom tags
  config.define_derived_metadata do |meta|
    meta[:slow] = true if meta[:disruptive]
  end
  
  # Example usage documentation
  config.before(:suite) do
    puts <<~MESSAGE

      #{"=" * 60}
      TEST FILTERING OPTIONS:
      #{"=" * 60}
      Run only read-only tests (default):
        bundle exec rspec

      Run only disruptive tests:
        bundle exec rspec --tag disruptive

      Run ALL tests (including disruptive):
        RSPEC_DISABLE_EXCLUSIONS=true bundle exec rspec

      Run specific file with all tests:
        RSPEC_DISABLE_EXCLUSIONS=true bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb

      #{"=" * 60}

    MESSAGE
  end
  
  # Network State Management for disruptive tests
  config.before(:suite) do
    # Only capture network state if disruptive tests will run
    # Check if disruptive tests are included (either explicitly or by not being excluded)
    disruptive_tests_will_run = !config.exclusion_filter[:disruptive] || 
                               config.inclusion_filter[:disruptive] ||
                               ENV['RSPEC_DISABLE_EXCLUSIONS'] == 'true'
    
    if disruptive_tests_will_run
      NetworkStateManager.capture_state
      $network_state_captured = true
    else
      $network_state_captured = false
    end
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
    # Only restore if we actually captured state
    if $network_state_captured
      network_state = NetworkStateManager.network_state
      if network_state && network_state[:network_name]
        puts "\n#{"=" * 60}"
        begin
          NetworkStateManager.restore_state
          puts "✅ Successfully restored network connection: #{network_state[:network_name]}"
        rescue => e
          puts <<~ERROR_MESSAGE
            ⚠️  Could not restore network connection: #{e.message}
            You may need to manually reconnect to: #{network_state[:network_name]}
          ERROR_MESSAGE
        end
        puts "#{"=" * 60}\n\n"
      end
    end
  end
  
end