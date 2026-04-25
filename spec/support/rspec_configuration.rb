# frozen_string_literal: true

require_relative 'network_state_manager'
require_relative 'test_helpers'
require_relative 'os_filtering'

module RSpecConfiguration
  VALID_REAL_ENV_TEST_OPTIONS = %w[none read_only all].freeze
  @sudo_tests_will_run = false
  @restore_failed = false

  def self.configure(config)
    configure_basic_settings(config)
    configure_test_ordering(config)
    configure_preflight_authentication(config)
    configure_test_stubbing(config)
    configure_network_state_management(config)
    configure_helper_inclusions(config)
  end

  # Basic RSpec configuration
  def self.configure_basic_settings(config)
    config.example_status_persistence_file_path = 'rspec-errors.txt'
    config.filter_run_including focus: true
    config.run_all_when_everything_filtered = !config.only_failures?

    configure_real_env_filtering(config)
    OSFiltering.setup_os_detection(config)
    OSFiltering.configure_os_filtering(config)

    config.define_derived_metadata do |meta|
      meta[:real_env] = true if meta[:real_env_read_only] || meta[:real_env_read_write]
      meta[:slow] = true if meta[:real_env_read_write]
    end
  end

  # Configure test execution order to run auth-requiring tests first
  def self.configure_test_ordering(config)
    auth_partition = ->(items) do
      items.partition do |item|
        needs_auth = item.metadata[:needs_sudo_access] || item.metadata[:keychain_integration]
        needs_auth || (
          item.respond_to?(:examples) &&
            item.examples.any? { |ex| ex.metadata[:needs_sudo_access] || ex.metadata[:keychain_integration] }
        )
      end
    end

    %i[sudo_first groups examples global].each do |ordering|
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
      examples_to_run = RSpecConfiguration.examples_to_run
      test_types = RSpecConfiguration.analyze_test_types(examples_to_run)
      RSpecConfiguration.note_auth_requirements(test_types)

      RSpecConfiguration.handle_real_env_preflight(test_types)
      RSpecConfiguration.handle_network_state_capture(test_types[:real_env_read_write])

      if RSpecConfiguration.macos_and_auth_tests_will_run?(test_types)
        RSpecConfiguration.handle_sudo_preflight(test_types[:sudo])
      end
    end
  end

  def self.note_auth_requirements(test_types)
    @sudo_tests_will_run = test_types[:sudo]
  end

  def self.examples_to_run
    if RSpec.world.respond_to?(:filtered_examples)
      RSpec.world.filtered_examples.values.flatten
    else
      []
    end
  end

  def self.analyze_test_types(examples_to_run)
    {
      real_env:            examples_to_run.any? { |ex| ex.metadata[:real_env] },
      real_env_read_write: examples_to_run.any? { |ex| ex.metadata[:real_env_read_write] },
      sudo:                examples_to_run.any? { |ex| ex.metadata[:needs_sudo_access] },
      keychain:            examples_to_run.any? { |ex| ex.metadata[:keychain_integration] },
    }
  end

  def self.macos_and_auth_tests_will_run?(test_types)
    defined?($compatible_os_tag) && $compatible_os_tag == :os_mac &&
      (test_types[:real_env] || test_types[:sudo] || test_types[:keychain])
  end

  def self.handle_sudo_preflight(sudo_tests_will_run)
    return unless sudo_tests_will_run

    system('sudo -v')
  end

  def self.refresh_sudo_ticket!(allow_prompt: false)
    return if system('sudo -n -v >/dev/null 2>&1')
    return if allow_prompt && system('sudo -v')

    raise 'sudo authentication expired before a :needs_sudo_access example ran. ' \
      'Re-run the suite and authenticate again.'
  end

  def self.keep_sudo_ticket_alive_for_real_env_write!
    return unless running_on_mac_os? && @sudo_tests_will_run

    refresh_sudo_ticket!
  end

  def self.handle_real_env_preflight(test_types)
    return unless running_on_mac_os?
    return unless test_types[:real_env]

    model = NetworkStateManager.model
    identity_error = real_env_wifi_identity_error(model)
    return unless identity_error

    raise real_env_wifi_identity_setup_error(identity_error)
  end

  def self.handle_network_state_capture(real_env_read_write_tests_will_run)
    return unless real_env_read_write_tests_will_run

    NetworkStateManager.start_session

    unless NetworkStateManager.model.connected?
      raise 'Real-environment read-write tests require an active network connection. ' \
        'Please connect to a WiFi network before running the read-write suite.'
    end

    NetworkStateManager.capture_state

    unless NetworkStateManager.network_state[:network_name]
      if running_on_mac_os?
        identity_error = real_env_wifi_identity_error(NetworkStateManager.model)
        raise real_env_wifi_identity_setup_error(identity_error) if identity_error
      end

      raise 'Real-environment read-write tests require a restorable network state. ' \
        'Connected state was detected but network name could not be determined.'
    end

    network_state = NetworkStateManager.network_state

    warn "\nCaptured network state for restoration: #{network_state[:network_name]}"
    if network_state[:network_password]
      warn 'Captured saved network password for restoration.'
    else
      warn 'Warning: No network password was captured during preflight. ' \
        'Restore may trigger additional macOS authentication prompts or fail to reconnect.'
    end
    warn ''
  end

  def self.ensure_network_state_capture!
    return if NetworkStateManager.state_available?

    handle_network_state_capture(true)
  end

  # Configure macOS-specific test stubbing that keeps ordinary specs isolated
  # from Keychain-backed password lookup behavior.
  #
  # In normal unit/read-only specs, we do not want `MacOsModel` to fall through
  # to real password retrieval paths, because those can trigger interactive
  # system prompts or depend on machine-specific Keychain state. The default
  # behavior here is therefore: if a spec is running in macOS test context and
  # is not explicitly tagged `:keychain_integration`, stub
  # `preferred_network_password` to return nil.
  #
  # Specs that intentionally exercise real Keychain behavior should opt in with
  # `:keychain_integration` so they can bypass this safety stub.
  def self.configure_test_stubbing(config)
    config.before do |example|
      next unless RSpecConfiguration.running_on_mac_os?

      unless example.metadata[:keychain_integration]
        allow_any_instance_of(WifiWand::MacOsModel)
          .to receive(:preferred_network_password)
          .and_return(nil)
      end

      security_regex = /\bsecurity\s+find-generic-password\b/

      allow_any_instance_of(WifiWand::CommandExecutor)
        .to receive(:run_command_using_args)
        .and_wrap_original do |method, command, *args, **kwargs|
        if command.to_s.match?(security_regex)
          raise os_command_error(exitstatus: 44, command: 'security', text: '')
        end

        method.call(command, *args, **kwargs)
      end
    end
  end

  def self.running_on_mac_os?
    defined?($compatible_os_tag) && $compatible_os_tag == :os_mac
  end

  # Configure helper method inclusions
  def self.configure_helper_inclusions(config)
    config.include(TestHelpers)
  end

  # Configure network state management for real-environment tests
  def self.configure_network_state_management(config)
    config.before(:each, :needs_sudo_access) do
      if RSpecConfiguration.running_on_mac_os?
        RSpecConfiguration.refresh_sudo_ticket!(allow_prompt: true)
      end
    end

    config.before(:each, :real_env_read_write) do
      RSpecConfiguration.keep_sudo_ticket_alive_for_real_env_write!
      RSpecConfiguration.ensure_network_state_capture!
    end

    config.after(:each, :real_env_read_write) do |_example|
      NetworkStateManager.restore_state(fail_silently: false)
      RSpecConfiguration.clear_restore_failure!
    rescue WifiWand::Error
      RSpecConfiguration.mark_restore_failure!
      raise
    end

    # Attempt final restoration and cleanup at end of test suite
    config.after(:suite) do
      RSpecConfiguration.attempt_final_network_restoration
      NetworkStateManager.clear_session
    end

    # Show usage information
    config.before(:suite) do
      RSpecConfiguration.show_test_usage_information
    end
  end

  def self.attempt_final_network_restoration
    network_state = NetworkStateManager.network_state
    return unless network_state && network_state[:network_name]
    return if previous_restore_failed?

    puts "\n#{'=' * 60}"
    begin
      NetworkStateManager.restore_state(fail_silently: false)
      puts "✅ Successfully restored network connection: #{network_state[:network_name]}"
    rescue WifiWand::Error => e
      safe_message = safe_utf8(e.message)
      safe_network_name = safe_utf8(network_state[:network_name])
      puts <<~ERROR_MESSAGE
        ⚠️  Could not restore network connection: #{safe_message}
        You may need to manually reconnect to: #{safe_network_name}
      ERROR_MESSAGE
      raise
    end
    puts "#{'=' * 60}\n\n"
  end

  def self.mark_restore_failure!
    @restore_failed = true
  end

  def self.clear_restore_failure!
    @restore_failed = false
  end

  def self.previous_restore_failed?
    !!@restore_failed
  end

  def self.safe_utf8(text)
    text.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '?')
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    text.to_s.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  end

  def self.real_env_wifi_identity_unverifiable?(model)
    !real_env_wifi_identity_error(model).nil?
  end

  def self.real_env_wifi_identity_error(model)
    return nil unless model.connected?

    begin
      network_name = model.connected_network_name
      return nil if network_name && !network_name.empty?
    rescue WifiWand::MacOsRedactionError => e
      return e
    rescue WifiWand::Error
      return WifiWand::Error.new('macOS cannot verify the current WiFi network identity')
    end

    WifiWand::Error.new('macOS cannot verify the current WiFi network identity')
  end

  def self.real_env_wifi_identity_setup_error(error)
    base_reason = if error.is_a?(WifiWand::MacOsRedactionError)
      error.reason
    else
      'macOS cannot verify the current WiFi network identity'
    end

    'Requested real-environment tests on macOS require unredacted WiFi identity because the suite must ' \
      'capture the starting SSID and verify restoration to that exact SSID afterward. ' \
      "wifi-wand can detect generic association, but #{base_reason}, so exact-state restoration of the " \
      'original network cannot be verified. Run `wifi-wand-macos-setup`, grant Location Services to ' \
      '`wifiwand-helper`, and rerun the tests.'
  end

  def self.show_test_usage_information
    puts <<~MESSAGE

      #{'=' * 60}
      TEST FILTERING OPTIONS:
      #{'=' * 60}
      Run only default mocked/hermetic tests:
        bundle exec rspec

      Run read-only real-environment tests, but skip host-mutating ones:
        WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec

      Run all real-environment tests, including read-write ones:
        WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec

      Current real environment setting: WIFIWAND_REAL_ENV_TESTS=#{ENV['WIFIWAND_REAL_ENV_TESTS'] || 'none'}

      Modifier env vars (orthogonal to test scope — combine with any of the above):
        WIFIWAND_VERBOSE=true  - show underlying OS commands
        COVERAGE_BRANCH=true   - enable branch coverage analysis
      Current: WIFIWAND_VERBOSE=#{ENV['WIFIWAND_VERBOSE'] || '[undefined]'}

      Coverage tracking is enabled via SimpleCov.
      HTML coverage report will be generated in coverage/index.html
      Default authoritative resultset: coverage/.resultset.json
      Real-environment resultset: coverage/.resultset.<os>.json

      ⚠️  IMPORTANT: Never run real-environment tests in CI environments.
      The default (WIFIWAND_REAL_ENV_TESTS unset) runs only safe tests.
      On macOS, requested real-environment runs are refused up front when the
      current WiFi SSID is redacted or otherwise unverifiable, because the
      suite must restore the exact original network state.

      #{'=' * 60}

    MESSAGE
  end

  def self.configure_real_env_filtering(config)
    option = ENV.fetch('WIFIWAND_REAL_ENV_TESTS', 'none')
    unless VALID_REAL_ENV_TEST_OPTIONS.include?(option)
      raise "Invalid WIFIWAND_REAL_ENV_TESTS option. Valid options: #{VALID_REAL_ENV_TEST_OPTIONS.join(', ')}"
    end

    case option
    when 'none'
      config.filter_run_excluding real_env: true
      # loopback_socket tests open a TCPServer on 127.0.0.1; skip them in
      # sandboxed environments that forbid socket creation.
      config.filter_run_excluding loopback_socket: true
    when 'read_only'
      config.filter_run_excluding real_env_read_write: true
    when 'all'
      # Run both ordinary and real-environment tests
    end
  end
end
