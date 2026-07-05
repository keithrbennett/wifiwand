# frozen_string_literal: true

module WifiWand
  module Models
    module Helpers
      module SecurityTypeNormalizer
        # Normalizes a raw security descriptor string from OS tools to
        # one of: "WPA3", "WPA2", "WPA", "WEP", "NONE", or nil (unknown/enterprise).
        def self.canonical_security_type_from(security_text)
          return nil if security_text.nil?

          text = security_text.to_s.strip
          return nil if text.empty?

          # Exclude enterprise/EAP networks which are not representable with PSK/WEP
          return nil if text.match?(/802\.?1x|enterprise/i)

          case text
          when /WPA3/i
            'WPA3'
          when /WPA2/i
            'WPA2'
          when /WPA1/i, /WPA(?!\d)/i
            'WPA'
          when /WEP/i
            'WEP'
          when /\bnone\b|spairport_security_mode_none/i, /\bowe\b/i
            'NONE'
          end
        end
      end
    end
  end
end
