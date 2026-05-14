# frozen_string_literal: true

require 'ipaddr'
require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/mac_os/dns_manager'

module WifiWand
  describe MacOsDnsManager do
    subject(:manager) do
      described_class.new(
        command_runner:    command_runner,
        service_name_proc: -> { service_name }
      )
    end

    let(:command_runner) { double('command_runner') }
    let(:service_name) { 'Wi-Fi' }

    describe '#nameservers_using_networksetup' do
      it 'parses networksetup DNS output correctly' do
        test_cases = [
          ["8.8.8.8\n1.1.1.1\n", ['8.8.8.8', '1.1.1.1']],
          ["There aren't any DNS Servers set on Wi-Fi.\n", []],
          ['192.168.1.1', ['192.168.1.1']],
        ]

        test_cases.each do |output, expected|
          allow(command_runner).to receive(:call)
            .with(['networksetup', '-getdnsservers', service_name])
            .and_return(command_result(stdout: output))

          expect(manager.nameservers_using_networksetup).to eq(expected)
        end
      end
    end

    describe '#nameservers_using_scutil' do
      it 'extracts unique nameservers from scutil output' do
        scutil_output = <<~OUTPUT
          resolver #1
            domain   : local
            options  : mdns
            timeout  : 5
            nameserver[0] : 8.8.8.8
            nameserver[1] : 1.1.1.1
            flags    : Request A records
          resolver #2
            nameserver[0] : 8.8.8.8
            nameserver[1] : 9.9.9.9
        OUTPUT

        allow(command_runner).to receive(:call).with(%w[scutil --dns])
          .and_return(command_result(stdout: scutil_output))

        expect(manager.nameservers_using_scutil).to contain_exactly('8.8.8.8', '1.1.1.1', '9.9.9.9')
      end
    end

    describe '#set_nameservers' do
      it 'handles different nameserver configurations' do
        test_cases = [
          { input: ['8.8.8.8', '1.1.1.1'], expected_args: ['8.8.8.8', '1.1.1.1'] },
          { input: ['192.168.1.1'], expected_args: ['192.168.1.1'] },
          { input: :clear, expected_args: ['empty'] },
        ]

        test_cases.each do |tc|
          expect(command_runner).to receive(:call)
            .with(['networksetup', '-setdnsservers', service_name] + tc[:expected_args])

          expect(manager.set_nameservers(tc[:input])).to eq(tc[:input])
        end
      end

      it 'accepts IPv6 DNS addresses' do
        ipv6_test_cases = [
          { input:         ['2606:4700:4700::1111', '2606:4700:4700::1001'],
            expected_args: ['2606:4700:4700::1111', '2606:4700:4700::1001'] },
          { input:         ['2001:4860:4860::8888'],
            expected_args: ['2001:4860:4860::8888'] },
          { input:         ['8.8.8.8', '2606:4700:4700::1111'],
            expected_args: ['8.8.8.8', '2606:4700:4700::1111'] },
        ]

        ipv6_test_cases.each do |tc|
          expect(command_runner).to receive(:call)
            .with(['networksetup', '-setdnsservers', service_name] + tc[:expected_args])

          expect(manager.set_nameservers(tc[:input])).to eq(tc[:input])
        end
      end

      it 'validates IP addresses and raises error for invalid ones' do
        invalid_nameservers = ['8.8.8.8', 'invalid.ip', '2001:db8:::1']

        silence_output do
          expect { manager.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to contain_exactly('invalid.ip', '2001:db8:::1')
            end
        end
      end

      it 'treats nil nameserver input as invalid' do
        invalid_nameservers = ['8.8.8.8', nil]

        silence_output do
          expect { manager.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq([nil])
            end
        end
      end

      it 'treats non-string nameserver input as invalid' do
        invalid_nameservers = ['8.8.8.8', 123]

        silence_output do
          expect { manager.set_nameservers(invalid_nameservers) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq([123])
            end
        end
      end

      it 'identifies mixed valid and invalid IP addresses' do
        mixed_ips = ['8.8.8.8', 'invalid.ip', '2606:4700:4700::1111', '1.1.1.1', '999.999.999.999']

        silence_output do
          invalid_ip_error = raise_error(WifiWand::InvalidIPAddressError) do |error|
            expect(error.invalid_addresses).to include('invalid.ip', '999.999.999.999')
            expect(error.invalid_addresses).not_to include('8.8.8.8', '1.1.1.1', '2606:4700:4700::1111')
          end
          expect { manager.set_nameservers(mixed_ips) }.to invalid_ip_error
        end
      end

      it 'treats IPAddr invalid-address errors as invalid input' do
        allow(IPAddr).to receive(:new).with('problematic.ip')
          .and_raise(IPAddr::InvalidAddressError, 'Parse error')
        allow(IPAddr).to receive(:new).with('8.8.8.8').and_call_original

        silence_output do
          expect { manager.set_nameservers(['8.8.8.8', 'problematic.ip']) }
            .to raise_error(WifiWand::InvalidIPAddressError) do |error|
              expect(error.invalid_addresses).to eq(['problematic.ip'])
            end
        end
      end
    end
  end
end
