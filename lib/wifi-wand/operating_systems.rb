require_relative 'error'
require_relative 'os/base_os'
require_relative 'os/mac_os'
require_relative 'os/ubuntu'

module WifiWand

# This class will be helpful in adding support for other OS's.
# To add an OS, see how each BaseOs subclass is implemented, implement it, and
# add it to the list of supported OS's.
#
# For the purpose of this program, an OS is defined as an approach to getting and setting
# wifi information. Therefore, although Ubuntu and RedHat are both Linux, they will probably
# need separate BaseOs subclasses.

class OperatingSystems


  attr_reader :supported_operating_systems


  def initialize
    @supported_operating_systems = [
        MacOs.new,
        Ubuntu.new
    ]
  end


  def current_os
    if @current_os.nil?
      matches = supported_operating_systems.select { |os| os.current_os_is_this_os? }
      if matches.size > 1
        matching_names = matches.map(&:display_name)
        raise Error.new("There should only be 1 matching OS, but there were multiple: #{matching_names.inspect}")
      end
      @current_os = matches.first
    end
    @current_os
  end


  def current_id;            current_os ? current_os.id : nil;            end
  def current_display_name;  current_os ? current_os.display_name : nil;  end

  # Class method to get the current OS without instantiating
  def self.current_os
    @current_os ||= new.current_os
  end
  
  # Class method to create a model for the current OS
  def self.create_model_for_current_os(options = OpenStruct.new)
    current_os_instance = current_os
    raise Error.new("No supported operating system detected") unless current_os_instance
    current_os_instance.create_model(options)
  end

end
end
