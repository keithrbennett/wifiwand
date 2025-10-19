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

  def wait_for(timeout: 5, interval: 0.1, description: "condition")
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
    group_disruptive = self.class.metadata[:disruptive] || self.class.parent_groups.any? { |group| group.metadata[:disruptive] }
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
end
