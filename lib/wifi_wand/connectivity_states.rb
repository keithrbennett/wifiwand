# frozen_string_literal: true

module WifiWand
  module ConnectivityStates
    CAPTIVE_PORTAL_LOGIN_REQUIRED = :yes
    CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED = :no
    CAPTIVE_PORTAL_LOGIN_UNKNOWN = :unknown

    INTERNET_REACHABLE = :reachable
    INTERNET_UNREACHABLE = :unreachable
    INTERNET_INDETERMINATE = :indeterminate
    INTERNET_PENDING = :pending

    module_function def internet_state_from_login_required(
      tcp_working:, dns_working:, captive_portal_login_required:
    )
      return INTERNET_UNREACHABLE unless tcp_working && dns_working

      case captive_portal_login_required
      when CAPTIVE_PORTAL_LOGIN_NOT_REQUIRED
        INTERNET_REACHABLE
      when CAPTIVE_PORTAL_LOGIN_REQUIRED
        INTERNET_UNREACHABLE
      else
        INTERNET_INDETERMINATE
      end
    end
  end
end
