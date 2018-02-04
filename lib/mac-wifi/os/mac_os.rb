require_relative 'base_os'

module MacWifi

class MacOs < BaseOs

  def initialize()
    super(:mac, 'Mac OS')
  end

  def current_os_is_this_os?
    !! /darwin/.match(RbConfig::CONFIG["host_os"])
  end

  def create_model(want_verbose)
    require_relative '../models/mac_os_model'
    MacOsModel.new(want_verbose)
  end
end
end
