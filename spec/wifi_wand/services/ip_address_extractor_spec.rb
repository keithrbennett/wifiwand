# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/services/ip_address_extractor'

RSpec.describe WifiWand::IPAddressExtractor do
  describe '.addresses' do
    it 'extracts IPv4 addresses from ifconfig and ip command output' do
      output = <<~OUT
        inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255
        inet 10.0.0.5/24 brd 10.0.0.255 scope global secondary
        inet6 2001:db8::1/64 scope global
      OUT

      addresses = described_class.addresses(output, line_type: 'inet', family: :ipv4)

      expect(addresses).to eq(['192.168.1.100', '10.0.0.5'])
    end

    it 'extracts IPv6 addresses and removes prefixes and scoped interface suffixes' do
      output = <<~OUT
        inet 192.168.1.100/24 brd 192.168.1.255 scope global
        inet6 fe80::1%en0 prefixlen 64 secured scopeid 0x6
        inet6 2001:db8::1/64 scope global dynamic
      OUT

      addresses = described_class.addresses(output, line_type: 'inet6', family: :ipv6)

      expect(addresses).to eq(['fe80::1', '2001:db8::1'])
    end

    it 'ignores malformed addresses and lines from the wrong family' do
      output = <<~OUT
        inet not-an-address netmask 0xffffff00
        inet6 2001:db8::1/64 scope global
      OUT

      addresses = described_class.addresses(output, line_type: 'inet', family: :ipv4)

      expect(addresses).to eq([])
    end
  end
end
