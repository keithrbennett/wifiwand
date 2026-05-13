# frozen_string_literal: true

module WifiWand
  module StringPredicates
    module_function def string_nil_or_empty?(value)
      value.nil? || (value.is_a?(String) && value.empty?)
    end

    module_function def string_nil_or_blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
