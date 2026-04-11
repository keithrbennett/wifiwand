# frozen_string_literal: true

module WifiWand
  module ConnectivityStates
    CAPTIVE_PORTAL_FREE = :free
    CAPTIVE_PORTAL_PRESENT = :present
    CAPTIVE_PORTAL_INDETERMINATE = :indeterminate

    INTERNET_REACHABLE = :reachable
    INTERNET_UNREACHABLE = :unreachable
    INTERNET_INDETERMINATE = :indeterminate
    INTERNET_PENDING = :pending

    module_function

    def internet_state_from(tcp_working:, dns_working:, captive_portal_state:)
      return INTERNET_UNREACHABLE unless tcp_working && dns_working

      case captive_portal_state
      when CAPTIVE_PORTAL_FREE
        INTERNET_REACHABLE
      when CAPTIVE_PORTAL_PRESENT
        INTERNET_UNREACHABLE
      else
        INTERNET_INDETERMINATE
      end
    end
  end
end
