# frozen_string_literal: true

require_relative 'wifi_wand/version'
require_relative 'wifi_wand/errors'
require_relative 'wifi_wand/string_predicates'
require_relative 'wifi_wand/timing'

# When additional operating systems are added, we will need to modify this
# to load only the model appropriate for the environment:

# Public API shortcuts
module WifiWand
  # Creates a model instance for the current operating system.
  # Delegates to WifiWand::Platforms::Selector.create_model_for_current_os.
  # @param options [Hash] options including :verbose and :wifi_interface
  def self.create_model(options = {})
    raise ArgumentError, 'options must be a Hash' unless options.is_a?(Hash)

    require_relative 'wifi_wand/platforms/selector'
    WifiWand::Platforms::Selector.create_model_for_current_os(options)
  end
end
