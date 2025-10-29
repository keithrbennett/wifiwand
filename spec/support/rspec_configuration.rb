# frozen_string_literal: true

require_relative '../network_state_manager'
require_relative 'test_helpers'
require_relative 'os_filtering'

module RSpecConfiguration
  def self.configure(config)
    configure_basic_settings(config)
    configure_test_ordering(config)
    configure_preflight_authentication(config)
    configure_test_stubbing(config)
    configure_network_state_management(config)
    configure_helper_inclusions(config)
  end

  private

  # Basic RSpec configuration
  def self.configure_basic_settings(config)
    config.example_status_persistence_file_path = 'rspec-errors.txt'
    config.filter_run_including :focus => true
    config.run_all_when_everything_filtered = !config.only_failures?
    
    configure_disruptive_test_filtering(config)
    OSFiltering.setup_os_detection(config)
    OSFiltering.configure_os_filtering(config)
    
    config.define_derived_metadata do |meta|
      meta[:slow] = true if meta[:disruptive]
    end
  end

  # Configure test execution order to run auth-requiring tests first
  def self.configure_test_ordering(config)
    auth_partition = ->(items) do
      items.partition do |it|
        needs_auth = it.metadata[:needs_sudo_access] || it.metadata[:keychain_integration]
        needs_auth || (
          it.respond_to?(:examples) && it.examples.any? { |ex| ex.metadata[:needs_sudo_access] || ex.metadata[:keychain_integration] }
        )
      end
    end

    [:sudo_first, :groups, :examples, :global].each do |ordering|
      config.register_ordering(ordering) do |items|
        auth_items, other_items = auth_partition.(items)
        auth_items + other_items
      end
    end

    config.order = :sudo_first
  end

  # Configure preflight authentication to handle auth prompts early
  def self.configure_preflight_authentication(config)
    config.before(:suite) do
      begin
        examples_to_run = RSpecConfiguration.get_examples_to_run
        test_types = RSpecConfiguration.analyze_test_types(examples_to_run)

        RSpecConfiguration.handle_network_state_capture(test_types[:disruptive])

        if RSpecConfiguration.macos_and_auth_tests_will_run?(test_types)
          RSpecConfiguration.handle_sudo_preflight(test_types[:sudo])
          RSpecConfiguration.handle_keychain_preflight(test_types[:disruptive])
        end
      rescue
        # Never fail the suite due to preflight issues
      end
    end
  end
  
  def self.get_examples_to_run
    if RSpec.world.respond_to?(:filtered_examples)
      RSpec.world.filtered_examples.values.flatten
    else
      []
    end
  end
  
  def self.analyze_test_types(examples_to_run)
    {
      disruptive: examples_to_run.any? { |ex| ex.metadata[:disruptive] },
      sudo: examples_to_run.any? { |ex| ex.metadata[:needs_sudo_access] },
      keychain: examples_to_run.any? { |ex| ex.metadata[:keychain_integration] }
    }
  end
  
  def self.macos_and_auth_tests_will_run?(test_types)
    defined?($compatible_os_tag) && $compatible_os_tag == :os_mac &&
      (test_types[:disruptive] || test_types[:sudo] || test_types[:keychain])
  end
  
  def self.handle_sudo_preflight(sudo_tests_will_run)
    return unless sudo_tests_will_run
    
    system('sudo -v')
    RSpecConfiguration.keep_sudo_alive
  end
  
  def self.handle_network_state_capture(disruptive_tests_will_run)
    return unless disruptive_tests_will_run
    
    begin
      NetworkStateManager.capture_state
    rescue => e
      puts "Warning: Could not capture network state during preflight: #{e.message}"
    end
  end
  
  def self.handle_keychain_preflight(disruptive_tests_will_run)
    return unless ENV['RSPEC_KEYCHAIN_PREFLIGHT'] == 'true' && !disruptive_tests_will_run
    
    model = NetworkStateManager.model rescue nil
    return unless model
    
    ssid = model.connected_network_name rescue nil
    return unless ssid
    
    begin
      model.preferred_network_password(ssid)
    rescue
      # Ignore – purpose is just to trigger auth prompt upfront
    end
  end
  
  def self.keep_sudo_alive
    $sudo_keepalive_thread = Thread.new do
      loop do
        system('sudo -n -v >/dev/null 2>&1')
        sleep 60
      end
    end
  rescue
    # If threading fails, don't break the suite
  end

  # Configure test stubbing to prevent keychain prompts during tests
  def self.configure_test_stubbing(config)
    config.before(:each) do |example|
      next unless RSpecConfiguration.macos_model_available?
      
      begin
        RSpecConfiguration.stub_keychain_access(example)
        RSpecConfiguration.stub_security_commands
      rescue
        # If stubbing fails, don't break the suite
      end
    end
  end
  
  def self.macos_model_available?
    defined?(WifiWand::MacOsModel) && ($compatible_os_tag == :os_mac)
  end
  
  def self.stub_keychain_access(example)
    return if example.metadata[:keychain_integration]
    
    allow_any_instance_of(WifiWand::MacOsModel)
      .to receive(:preferred_network_password)
      .and_return(nil)
  end

  # This method intercepts security commands to prevent keychain prompts
  # while allowing other OS commands to execute normally via .and_wrap_original
  def self.stub_security_commands
    security_regex = /\bsecurity\s+find-generic-password\b/

    allow_any_instance_of(WifiWand::CommandExecutor)
      .to receive(:run_os_command)
      .and_wrap_original do |method, command, *args|
        if command.to_s.match?(security_regex)
          raise WifiWand::CommandExecutor::OsCommandError.new(44, 'security', '')
        end

        method.call(command, *args)
      end
  end

  # Configure helper method inclusions
  def self.configure_helper_inclusions(config)
    config.include(TestHelpers)
  end
  
  # Configure network state management for disruptive tests
  def self.configure_network_state_management(config)
    # Restore network state after each disruptive test
    config.after(:each, :disruptive) do
      NetworkStateManager.restore_state
    end

    # Attempt final restoration and cleanup at end of test suite
    config.after(:suite) do
      RSpecConfiguration.cleanup_sudo_keepalive
      RSpecConfiguration.attempt_final_network_restoration
    end
    
    # Show usage information
    config.before(:suite) do
      RSpecConfiguration.show_test_usage_information
    end
  end
  
  def self.cleanup_sudo_keepalive
    return unless defined?($sudo_keepalive_thread) && $sudo_keepalive_thread&.alive?
    
    begin
      $sudo_keepalive_thread.kill
    rescue
      # Ignore cleanup errors
    end
  end
  
  def self.attempt_final_network_restoration
    examples_to_run = RSpecConfiguration.get_examples_to_run
    disruptive_tests_ran = examples_to_run.any? { |ex| ex.metadata[:disruptive] }
    
    return unless disruptive_tests_ran
    
    network_state = NetworkStateManager.network_state
    return unless network_state && network_state[:network_name]
    
    puts "\n#{'=' * 60}"
    begin
      NetworkStateManager.restore_state
      puts "✅ Successfully restored network connection: #{network_state[:network_name]}"
    rescue => e
      puts <<~ERROR_MESSAGE
        ⚠️  Could not restore network connection: #{e.message}
        You may need to manually reconnect to: #{network_state[:network_name]}
      ERROR_MESSAGE
    end
    puts "#{'=' * 60}\n\n"
  end
  
  def self.show_test_usage_information
    puts <<~MESSAGE

      #{'=' * 60}
      TEST FILTERING OPTIONS:
      #{'=' * 60}
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

      Coverage tracking is enabled via SimpleCov.
      HTML coverage report will be generated in coverage/index.html
      Enable branch coverage with COVERAGE_BRANCH=true

      ⚠️  IMPORTANT: Never run disruptive tests in CI environments.
      The default (RSPEC_DISRUPTIVE_TESTS unset) runs only safe tests.

      #{'=' * 60}

    MESSAGE
  end

  private

  def self.configure_disruptive_test_filtering(config)
    case ENV['RSPEC_DISRUPTIVE_TESTS']
    when 'only'
      config.filter_run_including :disruptive => true
    when 'include'
      # Run both disruptive and non-disruptive (no filters)
    when 'exclude', '', nil
      config.filter_run_excluding :disruptive => true
    else
      raise "Invalid RSPEC_DISRUPTIVE_TESTS option. Valid options: 'only', 'include', 'exclude', '', nil"
    end
  end
end
