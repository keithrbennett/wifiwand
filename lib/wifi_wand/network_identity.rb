# frozen_string_literal: true

module WifiWand
  module NetworkIdentity
    SSID_UNAVAILABLE_LABEL = '[SSID unavailable]'

    module_function def named?(network_name)
      !network_name.nil? && network_name != SSID_UNAVAILABLE_LABEL
    end
  end
end
