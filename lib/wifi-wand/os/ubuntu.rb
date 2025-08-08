require_relative 'base_os'

module WifiWand

class Ubuntu < BaseOs

  def initialize()
    super(:ubuntu, 'Ubuntu Linux')
  end

  def current_os_is_this_os?
    # Check for Ubuntu using multiple detection methods
    return true if File.exist?('/etc/os-release') && File.read('/etc/os-release').include?('ID=ubuntu')
    return true if system('lsb_release -i 2>/dev/null | grep -q "Ubuntu"')
    return true if File.exist?('/proc/version') && File.read('/proc/version').include?('Ubuntu')
    
    # Fallback: check if it's Linux (though this might be too broad)
    !! /linux/.match(RbConfig::CONFIG["host_os"].downcase)
  end

  def create_model(options)
    require_relative '../models/ubuntu_model'
    UbuntuModel.new(options)
  end
end
end