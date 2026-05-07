# frozen_string_literal: true

module WifiWandSpecSupport
  module Fakes
    class FakeConnectivityTester
      attr_accessor :tcp_result, :dns_result, :captive_result

      def initialize
        @tcp_result = true
        @dns_result = true
        @captive_result = WifiWand::ConnectivityStates::CAPTIVE_PORTAL_FREE
      end

      def tcp_connectivity?(timeout_in_secs: nil, return_details: false)
        evaluate(@tcp_result, timeout_in_secs: timeout_in_secs, return_details: return_details)
      end

      def dns_working?(timeout_in_secs: nil, return_details: false)
        evaluate(@dns_result, timeout_in_secs: timeout_in_secs, return_details: return_details)
      end

      def captive_portal_state(timeout_in_secs: nil)
        evaluate(@captive_result, timeout_in_secs: timeout_in_secs)
      end

      def internet_connectivity_state(tcp_working = nil, dns_working = nil, portal_state = nil,
        timeout_in_secs: nil)
        tcp_working = tcp_connectivity?(timeout_in_secs: timeout_in_secs) if tcp_working.nil?
        dns_working = dns_working?(timeout_in_secs: timeout_in_secs) if dns_working.nil?
        portal_state ||= captive_portal_state(timeout_in_secs: timeout_in_secs)

        WifiWand::ConnectivityStates.internet_state_from(
          tcp_working:          tcp_working,
          dns_working:          dns_working,
          captive_portal_state: portal_state
        )
      end

      private def evaluate(value, **)
        value = value.call(**) if value.respond_to?(:call)
        raise value if value.is_a?(Exception)

        value
      end
    end
  end
end
