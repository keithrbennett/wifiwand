# frozen_string_literal: true

# Base class for classes identifying a supported operating system.

require_relative '../../errors'

module WifiWand
  module Platforms
    module Selection
      Base = Struct.new(:id, :display_name) do
        def initialize(id, display_name)
          instantiated_by_subclass = (self.class.name != WifiWand::Platforms::Selection::Base.name)
          if instantiated_by_subclass
            super
          else
            # Prohibit Base.new call
            raise NonSubclassInstantiationError
          end
        end

        def current_os_is_this_os? = raise MethodNotImplementedError

        def create_model(_options) = raise MethodNotImplementedError
      end
    end
  end
end
