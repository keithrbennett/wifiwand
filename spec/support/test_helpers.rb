# frozen_string_literal: true

require 'ostruct'
require 'stringio'
require_relative '../network_state_manager'
require_relative '../../lib/wifi-wand/operating_systems'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

module TestHelpers
  def restore_network_state
    NetworkStateManager.restore_state
  end

  def network_state
    NetworkStateManager.network_state
  end

  # Helper method to create models with verbose configuration
  # Handles missing system commands gracefully for CI environments
  def create_test_model(options = {})
    merged_options = merge_verbose_options(options)
    current_os = WifiWand::OperatingSystems.current_os
    raise WifiWand::NoSupportedOSError.new unless current_os

    case current_os.id
    when :ubuntu
      model = WifiWand::UbuntuModel.new(merged_options)
      # Mock command availability to prevent missing utility errors in CI
      allow(model).to receive(:command_available?).and_return(true)
      # Mock WiFi interface detection to prevent hardware detection failures in CI
      # This can be overridden by individual tests that need to test interface detection failures
      allow(model).to receive(:detect_wifi_interface).and_return('wlp0s20f3')
      model.init
      model
    when :mac
      # Mac models don't have the same command validation issues, but need interface detection stubbing
      # Stub interface detection methods to prevent real network calls during model creation
      allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0')
      allow_any_instance_of(WifiWand::MacOsModel).to receive(:fetch_hardware_ports).and_return([
        { name: 'Wi-Fi', device: 'en0', ethernet_address: '34:b1:eb:f3:b8:1c' },
        { name: 'Ethernet', device: 'en1', ethernet_address: 'aa:bb:cc:dd:ee:ff' }
      ])
      helper_client = instance_double(
        WifiWand::MacOsWifiAuthHelper::Client,
        connected_network_name: nil,
        scan_networks: []
      )
      allow(WifiWand::MacOsWifiAuthHelper::Client).to receive(:new).and_return(helper_client)
      WifiWand::MacOsModel.create_model(merged_options)
    else
      raise WifiWand::NoSupportedOSError.new
    end
  end

  # Helper method to create specific OS models with verbose configuration
  def create_ubuntu_test_model(options = {})
    WifiWand::UbuntuModel.new(merge_verbose_options(options))
  end

  def create_mac_os_test_model(options = {})
    WifiWand::MacOsModel.new(merge_verbose_options(options))
  end

  def wait_for(timeout: 5, interval: 0.1, description: 'condition')
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      return if yield # The block returns true, so we exit successfully

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time > timeout
        raise "Timeout after #{timeout}s waiting for #{description}"
      end

      sleep(interval)
    end
  end

  def is_disruptive?
    current_example = RSpec.current_example
    example_disruptive = current_example&.metadata&.fetch(:disruptive, nil)
    group_disruptive = self.class.metadata[:disruptive] || self.class.parent_groups.any? { |group|
 group.metadata[:disruptive] }
    example_disruptive || group_disruptive
  end

  private

  # Merges verbose setting from environment with test options
  def merge_verbose_options(options = {})
    # Check for verbose mode from environment variable (as default)
    verbose = ENV['WIFIWAND_VERBOSE'] == 'true'

    # Merge environment default with provided options (options override env)
    OpenStruct.new({ verbose: verbose }.merge(options))
  end

  # Suppress stdout/stderr within the given block
  def silence_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield $stdout, $stderr
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Color assertion constants for testing TTY-aware output
  ANSI_COLOR_REGEX = /\e\[\d+m/
  GREEN_TEXT_REGEX = /\e\[32m.*\e\[0m/
  RED_TEXT_REGEX = /\e\[31m.*\e\[0m/
  YELLOW_TEXT_REGEX = /\e\[33m.*\e\[0m/
  CYAN_TEXT_REGEX = /\e\[36m.*\e\[0m/

  # Factory method for creating standard CLI mock model with common methods
  def create_standard_mock_model(overrides = {})
    defaults = {
      verbose_mode: false,
      wifi_on?: true,
      wifi_off: nil,
      wifi_on: nil,
      available_network_names: ['TestNet1', 'TestNet2'],
      wifi_info: {'status' => 'connected'},
      connected_to_internet?: true,
      connected_network_name: 'TestNetwork',
      disconnect: nil,
      connect: nil,
      cycle_network: nil,
      nameservers: ['8.8.8.8', '1.1.1.1'],
      set_nameservers: nil,
      preferred_networks: ['Network1', 'Network2'],
      preferred_network_password: 'password123',
      remove_preferred_networks: ['RemovedNet'],
      till: nil,
      last_connection_used_saved_password?: false,
      available_resources_help: 'Available resources help text',
      open_resources_by_codes: { opened_resources: [], invalid_codes: [] },
      resource_manager: double('resource_manager', invalid_codes_error: 'Invalid codes'),
      generate_qr_code: 'TestNetwork-qr-code.png'
    }
    double('model', defaults.merge(overrides))
  end

  # Factory method for creating mock OS with a model
  def create_mock_os_with_model(model = nil)
    model ||= create_standard_mock_model
    double('os', create_model: model)
  end

  # Factory method for creating CLI options
  def create_cli_options(overrides = {})
    defaults = {
      verbose: false,
      wifi_interface: nil,
      interactive_mode: false,
      post_processor: nil
    }
    OpenStruct.new(defaults.merge(overrides))
  end

  # Helper for mocking Socket.tcp failures
  def mock_socket_connection_failure
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
  end

  # Helper for mocking Socket.tcp success
  def mock_socket_connection_success
    allow(Socket).to receive(:tcp).and_yield
  end

  # Helper for mocking IPSocket.getaddress failures
  def mock_dns_resolution_failure
    allow(IPSocket).to receive(:getaddress).and_raise(SocketError)
  end

  # Helper for mocking IPSocket.getaddress success
  def mock_dns_resolution_success(ip_address = '1.2.3.4')
    allow(IPSocket).to receive(:getaddress).and_return(ip_address)
  end

  # Helper for stubbing short connectivity timeouts for fast tests
  def stub_short_connectivity_timeouts
    stub_const('WifiWand::TimingConstants::OVERALL_CONNECTIVITY_TIMEOUT', 0.05)
    stub_const('WifiWand::TimingConstants::TCP_CONNECTION_TIMEOUT', 0.01)
    stub_const('WifiWand::TimingConstants::DNS_RESOLUTION_TIMEOUT', 0.01)
  end
end
