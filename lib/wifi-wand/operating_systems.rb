# frozen_string_literal: true

require_relative 'errors'
require_relative 'os/base_os'
require_relative 'os/mac_os'
require_relative 'os/ubuntu'

module WifiWand

# This class will be helpful in adding support for other OS's.
# To add an OS, see how each BaseOs subclass is implemented, implement it, and
# add it to the list of supported OS's.
#
# For the purpose of this program, an OS is defined as an approach to getting and setting
# WiFi information. Therefore, although Ubuntu and RedHat are both Linux, they will probably
# need separate BaseOs subclasses.

class OperatingSystems
  class << self
    def supported_operating_systems
      @supported_operating_systems ||= [
        MacOs.new,
        Ubuntu.new
      ]
    end

    def current_os
      @current_os ||= begin
        matches = supported_operating_systems.select { |os| os.current_os_is_this_os? }
        if matches.size > 1
          matching_names = matches.map(&:display_name)
          raise MultipleOSMatchError.new(matching_names)
        end
        matches.first # nil for an unrecognized OS
      end
    end

    def current_id
      current_os&.id
    end

    def current_display_name
      current_os&.display_name
    end

    def create_model_for_current_os(options = {})
      options = OpenStruct.new(options) if options.is_a?(Hash)
      current_os_instance = current_os
      raise NoSupportedOSError.new unless current_os_instance
      current_os_instance.create_model(options)
    end
  end

  private_class_method :new
end
end
