# frozen_string_literal: true

require 'ipaddr'

module WifiWand
  module IPAddressExtractor
    def self.addresses(output, line_type:, family:)
      output.each_line.filter_map do |line|
        address_from_line(line, line_type: line_type, family: family)
      end
    end

    def self.address_from_line(line, line_type:, family:)
      tokens = line.split
      return nil unless tokens.first == line_type

      normalized_address(tokens[1], family: family)
    end

    def self.normalized_address(address_token, family:)
      address = address_token&.split('/')&.first
      address = address&.split('%')&.first if family == :ipv6
      return nil if address.nil? || address.empty?

      parsed_address = IPAddr.new(address)
      return nil unless expected_family?(parsed_address, family)

      address
    rescue IPAddr::InvalidAddressError
      nil
    end

    def self.expected_family?(address, family)
      case family
      when :ipv4
        address.ipv4?
      when :ipv6
        address.ipv6?
      else
        raise ArgumentError, "Unknown IP address family: #{family.inspect}"
      end
    end
  end
end
