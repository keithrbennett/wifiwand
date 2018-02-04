module MacWifi

# This class will be helpful in adding support for other OS's.
# To add an OS, see how each OS object is created and added to the list of supported OS's.
#
# For the purpose of this program, and OS is defined as an approach to getting and setting
# wifi information. Therefore, although Ubuntu and RedHat are both Linux, they will probably
# need separate OS entries.
class OperatingSystems


  class OS < Struct.new(:id, :display_name, :model_class, :test_predicate); end

  attr_reader :supported_operating_systems


  MAC_OS = OS.new(:mac, 'Mac OS', MacWifi::MacOsModel, -> do
    !! /darwin/.match(RbConfig::CONFIG["host_os"])
  end)

  IMAGINARY_OS = OS.new(:imaginary, 'Imaginary OS', nil, -> do
    !! ENV['IMAGINARY_OS']
  end)


  def initialize
    @supported_operating_systems = [
        MAC_OS,
        IMAGINARY_OS
    ]
  end


  def current_os
    @current_os ||= supported_operating_systems.detect { |os| os.test_predicate.() }
  end


  def create_model
    
  end

  def supported_os_names
    supported_operating_systems.map(&:display_name)
  end


  def current_id;            current_os&.id;            end
  def current_display_name;  current_os&.display_name;  end
  def current_model_class;   current_os&.model_class;   end

end
end
