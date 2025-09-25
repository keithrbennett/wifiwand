# frozen_string_literal: true

require_relative '../network_state_manager'
require_relative 'test_helpers'
require_relative 'os_filtering'

module RSpecConfiguration
  def self.configure(config)
    config.example_status_persistence_file_path = 'rspec-errors.txt'

    # Enable RSpec tags
    config.filter_run_including :focus => true
    # Avoid running the entire suite when using --only-failures and the filter matches nothing
    config.run_all_when_everything_filtered = !config.only_failures?
    
    configure_disruptive_test_filtering(config)
    
    # Setup OS detection and filtering
    OSFiltering.setup_os_detection(config)
    OSFiltering.configure_os_filtering(config)
    
    # Add custom tags
    config.define_derived_metadata do |meta|
      meta[:slow] = true if meta[:disruptive]
    end
    
    # Run auth-related tests first to get authentication prompts out of the way early
    # Consider both sudo-requiring tests and keychain integration tests
    auth_partition = ->(items) do
      items.partition do |it|
        needs_auth = it.metadata[:needs_sudo_access] || it.metadata[:keychain_integration]
        needs_auth || (
          it.respond_to?(:examples) && it.examples.any? { |ex| ex.metadata[:needs_sudo_access] || ex.metadata[:keychain_integration] }
        )
      end
    end

    config.register_ordering(:sudo_first) do |items|
      auth_items, other_items = auth_partition.(items)
      auth_items + other_items
    end

    config.register_ordering(:groups) do |groups|
      auth_groups, other_groups = auth_partition.(groups)
      auth_groups + other_groups
    end

    config.register_ordering(:examples) do |examples|
      auth_examples, other_examples = auth_partition.(examples)
      auth_examples + other_examples
    end

    # Use the custom ordering for the entire suite (examples and groups)
    config.order = :sudo_first

    # Keep a global nudge as well, though :groups/:examples should be sufficient
    config.register_ordering(:global) do |items|
      auth_items, other_items = auth_partition.(items)
      auth_items + other_items
    end

    # Pre-flight authentication for macOS to surface prompts only when needed
    config.before(:suite) do
      # Never attempt auth/network preflight in CI
      next if ENV['CI']
      begin
        # Determine which examples RSpec will actually run after filters
        examples_to_run = if RSpec.world.respond_to?(:filtered_examples)
                            RSpec.world.filtered_examples.values.flatten
                          else
                            []
                          end

        disruptive_tests_will_run = examples_to_run.any? { |ex| ex.metadata[:disruptive] }
        sudo_tests_will_run       = examples_to_run.any? { |ex| ex.metadata[:needs_sudo_access] }
        keychain_tests_will_run   = examples_to_run.any? { |ex| ex.metadata[:keychain_integration] }

        # Preflight on macOS when any auth-relevant tests will run
        if defined?($compatible_os_tag) && $compatible_os_tag == :os_mac && (disruptive_tests_will_run || sudo_tests_will_run || keychain_tests_will_run)
          # Warm up sudo timestamp only if sudo-tagged tests will run (no-op if already cached)
          system('sudo -v') if sudo_tests_will_run

          # Build a model to query current state
          model = begin
            NetworkStateManager.model
          rescue
            nil
          end

          if model
            # Capture network state during preflight when authentication is available
            # This ensures we have the password before test stubbing begins
            if disruptive_tests_will_run
              begin
                # Capture network state with authentication available
                NetworkStateManager.capture_state
              rescue => e
                # Log but don't fail the suite
                puts "Warning: Could not capture network state during preflight: #{e.message}"
              end
            end
            
            # Additional keychain preflight for keychain integration tests
            # Only when explicitly enabled and no disruptive tests (to avoid double auth)
            if ENV['RSPEC_KEYCHAIN_PREFLIGHT'] == 'true' && !disruptive_tests_will_run
              ssid = begin
                model.connected_network_name
              rescue
                nil
              end
              if ssid
                begin
                  model.preferred_network_password(ssid)
                rescue
                  # Ignore – purpose is just to trigger any auth prompt upfront
                end
              end
            end

            # Trigger a harmless sudo networksetup operation early only when sudo-tagged tests will run
            if sudo_tests_will_run
              iface = begin
                model.wifi_interface
              rescue
                'en0'
              end
              system("sudo networksetup -removepreferredwirelessnetwork #{iface} non_existent_network_123 >/dev/null 2>&1 || true")
            end
          end
          
          # Keep sudo timestamp alive during the suite to avoid later prompts
          if sudo_tests_will_run
            begin
              $sudo_keepalive_thread = Thread.new do
                loop do
                  # Non-interactive refresh; no prompt if credentials expire
                  system('sudo -n -v >/dev/null 2>&1')
                  sleep 60
                end
              end
            rescue
              # If threading fails for any reason, don't break the suite
            end
          end
        end
      rescue
        # Never fail the suite due to preflight convenience
      end
    end

    # (Removed preferred network password logging per project decision)
    
    # Include test helper methods
    config.include(TestHelpers)

    # Prevent accidental macOS Keychain UI prompts in tests on macOS
    config.before(:each) do |example|
      begin
        if defined?(WifiWand::MacOsModel) && ($compatible_os_tag == :os_mac)
          # By default, stub the high-level helper to avoid Keychain access from indirect paths
          unless example.metadata[:keychain_integration]
            allow_any_instance_of(WifiWand::MacOsModel)
              .to receive(:preferred_network_password)
              .and_return(nil)
          end

          allow_any_instance_of(WifiWand::MacOsModel)
            .to receive(:run_os_command)
            .and_wrap_original do |m, *args|
              cmd = args.first.to_s
              if cmd.match?(/\bsecurity\s+find-generic-password\b/)
                raise WifiWand::CommandExecutor::OsCommandError.new(44, 'security', '')
              else
                m.call(*args)
              end
            end
        end
      rescue => _e
        # If stubbing fails for any reason, do not break the suite
      end
    end
    
    setup_test_suite_hooks(config)
    setup_network_state_management(config)

    # Verbose mode now strictly respects ENV['WIFIWAND_VERBOSE'] or per-test options.
    # Use helpers like `silence_output` in specs to suppress only targeted noise.
  end

  private

  def self.configure_disruptive_test_filtering(config)
    # In CI, never run disruptive tests that change host network state
    if ENV['CI']
      config.filter_run_excluding :disruptive => true
      return
    end

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

  def self.setup_test_suite_hooks(config)
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

        Coverage tracking is enabled via SimpleCov. 
        HTML coverage report will be generated in coverage/index.html
        Enable branch coverage with COVERAGE_BRANCH=true
        Enforce coverage thresholds with COVERAGE_STRICT=true

        #{"=" * 60}

      MESSAGE
    end
  end

  def self.setup_network_state_management(config)
    # Network State Management for disruptive tests
    config.before(:suite) do
      # Determine examples RSpec will actually run after filters (e.g., --only-failures)
      examples_to_run = if RSpec.world.respond_to?(:filtered_examples)
                          RSpec.world.filtered_examples.values.flatten
                        else
                          []
                        end

      # Only show messages and validate sudo if disruptive tests are actually scheduled to run
      disruptive_tests_will_run = examples_to_run.any? { |ex| ex.metadata[:disruptive] }
      sudo_tests_will_run       = examples_to_run.any? { |ex| ex.metadata[:needs_sudo_access] }
      
      if disruptive_tests_will_run
        if RUBY_PLATFORM.include?('darwin')
          # Build a dynamic list of examples that require sudo access
          begin
            # Gather all examples from example groups recursively
            def self.__collect_examples(group)
              examples = []
              examples.concat(group.examples) if group.respond_to?(:examples)
              child_groups = if group.respond_to?(:children)
                               group.children
                             elsif group.respond_to?(:example_groups)
                               group.example_groups
                             else
                               []
                             end
              child_groups.each { |child| examples.concat(__collect_examples(child)) }
              examples
            end

            # Prefer the set of examples RSpec will actually run after filters (e.g., --only-failures)
            if RSpec.world.respond_to?(:filtered_examples)
              examples_to_run = RSpec.world.filtered_examples.values.flatten
            else
              top_groups = RSpec.world.respond_to?(:example_groups) ? RSpec.world.example_groups : []
              examples_to_run = top_groups.flat_map { |g| __collect_examples(g) }
            end

            # Filter to those explicitly requiring sudo access among examples that will run
            sudo_examples = examples_to_run.select { |ex| ex.metadata[:needs_sudo_access] }
            formatted = if sudo_examples.any?
              sudo_examples.map do |ex|
                name = ex.full_description
                file = ex.metadata[:file_path]
                line = ex.metadata[:line_number]
                "- #{name}: #{file}:#{line}"
              end.join("\n")
            else
              "(no tests tagged :needs_sudo_access)"
            end

            puts <<~MESSAGE
              
              #{"=" * 60}
              AUTHENTICATION MAY BE REQUIRED FOR DISRUPTIVE TESTS
              #{"=" * 60}
              Tests that require sudo access:
              
              #{formatted}
              
              Please be available to respond to authentication prompts
              during test execution.
              #{"=" * 60}

            MESSAGE
          rescue => e
            # Fallback to a simple notice if we cannot enumerate examples
            puts <<~FALLBACK
              
              #{"=" * 60}
              AUTHENTICATION MAY BE REQUIRED FOR DISRUPTIVE TESTS
              #{"=" * 60}
              (Could not enumerate :needs_sudo_access specs: #{e.class}: #{e.message})
              #{"=" * 60}

            FALLBACK
          end

          # Validate sudo timestamp only if at least one sudo-tagged example will run
          if sudo_tests_will_run
            puts "\nAttempting to validate sudo timestamp..."
            system("sudo -v")
            unless $?.success?
              abort "❌ Sudo validation failed. Please run 'sudo -v' manually and enter your password before starting the test suite."
            end
            puts "✅ Sudo timestamp validated."
          end
        end
        
      end
    end
    
    # Restore network state after each disruptive test
    config.after(:each, :disruptive) do
      NetworkStateManager.restore_state
    end

    # Attempt final restoration at the end of test suite
    config.after(:suite) do
      # Stop sudo keepalive if started
      begin
        if defined?($sudo_keepalive_thread) && $sudo_keepalive_thread&.alive?
          $sudo_keepalive_thread.kill
        end
      rescue
        # ignore
      end

      # Only restore if disruptive tests ran (check the same way as preflight)
      examples_to_run = if RSpec.world.respond_to?(:filtered_examples)
                          RSpec.world.filtered_examples.values.flatten
                        else
                          []
                        end
      disruptive_tests_ran = examples_to_run.any? { |ex| ex.metadata[:disruptive] }
      
      if disruptive_tests_ran
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

  def self.prompt_for_macos_keychain_access
    puts <<~MESSAGE

      #{"=" * 60}
      KEYCHAIN ACCESS SETUP FOR DISRUPTIVE TESTS
      #{"=" * 60}
      Disruptive tests may access WiFi passwords from your keychain.
      If prompted, please grant access to enable comprehensive testing.
      This allows testing of:
        • Preferred network password retrieval
        • Network connection with saved credentials
      #{"=" * 60}

    MESSAGE
  rescue => e
    puts "Warning: Could not display keychain access information: #{e.message}"
  end
end
