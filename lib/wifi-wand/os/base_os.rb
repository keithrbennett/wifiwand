# Base class for classes identifying a supported operating system.

module WifiWand

class BaseOs < Struct.new(:id, :display_name)

  class NonSubclassInstantiationError < RuntimeError
    def to_s
      "Class #{self.class} can only be instantiated by subclasses"
    end
  end

  def initialize(id, display_name)
    instantiated_by_subclass = (self.class.name != WifiWand::BaseOs.name)
    if instantiated_by_subclass
      super
    else
      raise NonSubclassInstantiationError.new
    end
  end

  class MethodNotImplementedError < RuntimeError

    def to_s
      "The #{self.class} class is not intended to be instantiated directly. Instantiate a subclass of it."
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
