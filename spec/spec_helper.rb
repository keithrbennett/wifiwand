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
    
    # Configure disruptive test filtering
    case ENV['RSPEC_DISRUPTIVE_TESTS']
    when 'only'
      config.filter_run_including :disruptive => true
    when 'include'
      # Run both disruptive and non-disruptive (no filters)
    when 'exclude'
      config.filter_run_excluding :disruptive => true
    else
      # Default: exclude disruptive tests
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
      Run only read-only (nondisruptive) tests:
        bundle exec rspec
        or
        RSPEC_DISRUPTIVE_TESTS=exclude bundle exec rspec

      Run ONLY disruptive native OS tests:
        RSPEC_DISRUPTIVE_TESTS=only bundle exec rspec

      Run ALL native OS tests (including disruptive):
        RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec

      Verbose mode for WifiWand commands can be enabled by setting WIFIWAND_VERBOSE=true.
      Current environment setting: WIFIWAND_VERBOSE=#{ENV['WIFIWAND_VERBOSE'] || '[undefined]'}

      #{"=" * 60}

    MESSAGE
  end
  
  # Network State Management for disruptive tests
  config.before(:suite) do
    # Only capture network state if disruptive tests will run
    # Check if disruptive tests are included (either explicitly or by not being excluded)
    disruptive_tests_will_run = !config.exclusion_filter[:disruptive] || 
                               config.inclusion_filter[:disruptive] ||
                               ENV['RSPEC_DISRUPTIVE_TESTS'] == 'include' ||
                               ENV['RSPEC_DISRUPTIVE_TESTS'] == 'only'
    
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

    # Helper method to create models with verbose configuration
    def create_test_model(options = {})
      WifiWand::OperatingSystems.create_model_for_current_os(merge_verbose_options(options))
    end

    # Helper method to create specific OS models with verbose configuration
    def create_ubuntu_test_model(options = {})
      WifiWand::UbuntuModel.create_model(merge_verbose_options(options))
    end

    def create_mac_os_test_model(options = {})
      WifiWand::MacOsModel.create_model(merge_verbose_options(options))
    end

    private

    # Merges verbose setting from environment with test options
    def merge_verbose_options(options = {})
      # Check for verbose mode from environment variable (as default)
      verbose = ENV['WIFIWAND_VERBOSE'] == 'true'
      
      # Merge environment default with provided options (options override env)
      OpenStruct.new({ verbose: verbose }.merge(options))
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