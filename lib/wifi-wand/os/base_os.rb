# frozen_string_literal: true

# Base class for classes identifying a supported operating system.

require_relative '../errors'

module WifiWand
  BaseOs = Struct.new(:id, :display_name) do
    def initialize(id, display_name)
      instantiated_by_subclass = (self.class.name != WifiWand::BaseOs.name)
      if instantiated_by_subclass
        super
      else
        # Prohibit BaseOs.new call
        raise NonSubclassInstantiationError
      end
    end

    def current_os_is_this_os? = raise MethodNotImplementedError

    def create_model(_options) = raise MethodNotImplementedError
  end
end
