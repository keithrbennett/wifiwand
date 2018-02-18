require_relative 'os/base_os'
require_relative 'os/imaginary_os'
require_relative 'os/mac_os'

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
        ImaginaryOs.new,
        MacOs.new
    ]
  end


  def current_os
    if @current_os.nil?
      matches = supported_operating_systems.select { |os| os.current_os_is_this_os? }
      if matches.size > 1
        matching_names = matches.map(&:display_name)
        raise "There should only be 1 matching OS, but there were multiple: #{matching_names.inspect}"
      end
      @current_os = matches.first
    end
    @current_os
  end


  def current_id;            current_os&.id;            end
  def current_display_name;  current_os&.display_name;  end

end
end
