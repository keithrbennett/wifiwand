require 'ostruct'
require_relative '../network_state_manager'
require_relative '../../lib/wifi-wand/operating_systems'

module TestHelpers
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
end