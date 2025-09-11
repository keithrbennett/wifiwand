# frozen_string_literal: true

# Base class for classes identifying a supported operating system.

require_relative '../errors'

module WifiWand

class BaseOs < Struct.new(:id, :display_name)

  class NonSubclassInstantiationError < Error
    def to_s
      "Class #{self.class} can only be instantiated by subclasses"
    end
  end

  def initialize(id, display_name)
    instantiated_by_subclass = (self.class.name != WifiWand::BaseOs.name)
    if instantiated_by_subclass
      super
    else
      # Prohibit BaseOs.new call
      raise NonSubclassInstantiationError.new
    end
  end

  class MethodNotImplementedError < Error

    def to_s
      "This method is not implemented in this base class. It must be implemented in, and called on, a subclass."
    end
  end

  def current_os_is_this_os?
    raise MethodNotImplementedError.new
  end

  def create_model(options)
    raise MethodNotImplementedError.new
  end

end
end
