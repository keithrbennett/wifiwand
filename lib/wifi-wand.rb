require_relative 'wifi-wand/version'

require_relative 'wifi-wand/main'  # recursively requires the other files
#
# When additional operating systems are added, we will need to modify this
# to load only the model appropriate for the environment:

# Public API shortcuts
module WifiWand
  # Creates a model instance for the current operating system.
  # Delegates to WifiWand::OperatingSystems.create_model_for_current_os.
  # @param options [OpenStruct] options including :verbose and :wifi_interface
  def self.create_model(options = OpenStruct.new)
    require_relative 'wifi-wand/operating_systems'
    WifiWand::OperatingSystems.create_model_for_current_os(options)
  end
end
