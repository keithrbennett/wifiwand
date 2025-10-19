# frozen_string_literal: true

require_relative 'base_os'

module WifiWand

class Ubuntu < BaseOs

  def initialize()
    super(:ubuntu, 'Ubuntu Linux')
  end

  def current_os_is_this_os?
    # Check /etc/os-release for Ubuntu or Ubuntu-based systems
    if File.exist?('/etc/os-release')
      content = File.read('/etc/os-release')

      # Direct Ubuntu match (official Ubuntu and flavors)
      return true if content.match?(/^ID=ubuntu$/m)

      # Ubuntu derivative match (Linux Mint, Pop!_OS, elementary OS, etc.)
      # These systems have ID=something_else but ID_LIKE contains "ubuntu"
      return true if content.match?(/^ID_LIKE=.*ubuntu/m)
    end

    # Fallback: check /proc/version for Ubuntu signature
    return true if File.exist?('/proc/version') && File.read('/proc/version').include?('Ubuntu')

    # Not Ubuntu or Ubuntu-based
    false
  end

  def create_model(options)
    require_relative '../models/ubuntu_model'
    UbuntuModel.create_model(options)
  end
end
end