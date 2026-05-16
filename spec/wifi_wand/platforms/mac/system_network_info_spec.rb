# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/platforms/mac/system_network_info'

module WifiWand
  describe Platforms::Mac::SystemNetworkInfo do
    subject(:info) do
      described_class.new(
        command_runner:          command_runner,
        wifi_interface_provider: -> { wifi_interface }
      )
    end

    let(:command_runner) { double('command_runner') }
    let(:wifi_interface) { 'en0' }

    describe '#ipv4_addresses' do
      it 'handles different ifconfig responses' do
        test_cases = [
          ["\tinet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255\n", ['192.168.1.100']],
          ["\tinet 192.168.1.100 netmask 0xffffff00\n\tinet 10.0.0.5 netmask 0xffffff00\n",
            ['192.168.1.100', '10.0.0.5']],
          ["\tinet6 fe80::1%en0 prefixlen 64 secured scopeid 0x6\n", []],
          ['', []],
          [os_command_error(exitstatus: 1, command: 'ifconfig', text: ''), []],
        ]

        test_cases.each do |response, expected|
          if response.is_a?(Exception)
            allow(command_runner).to receive(:call).and_raise(response)
          else
            allow(command_runner).to receive(:call).and_return(command_result(stdout: response))
          end

          expect(info.ipv4_addresses).to eq(expected)
        end
      end

      it 're-raises unexpected ifconfig errors' do
        allow(command_runner).to receive(:call).and_raise(
          os_command_error(exitstatus: 2, command: 'ifconfig', text: 'boom')
        )

        expect { info.ipv4_addresses }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'accepts an explicit interface and timeout for bounded status lookups' do
        expect(command_runner).to receive(:call)
          .with(%w[ifconfig en1], timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "\tinet 192.168.1.5 netmask 0xffffff00\n"))

        expect(info.ipv4_addresses(iface: 'en1', timeout_in_secs: 0.25)).to eq(['192.168.1.5'])
      end
    end

    describe '#ipv6_addresses' do
      it 'handles different ifconfig responses' do
        test_cases = [
          ["\tinet6 fe80::1%en0 prefixlen 64 secured scopeid 0x6\n", ['fe80::1']],
          ["\tinet6 fe80::1%en0 prefixlen 64\n\tinet6 2001:db8::5 prefixlen 64\n",
            ['fe80::1', '2001:db8::5']],
          ["\tinet 192.168.1.100 netmask 0xffffff00\n", []],
          ['', []],
          [os_command_error(exitstatus: 1, command: 'ifconfig', text: ''), []],
        ]

        test_cases.each do |response, expected|
          if response.is_a?(Exception)
            allow(command_runner).to receive(:call).and_raise(response)
          else
            allow(command_runner).to receive(:call).and_return(command_result(stdout: response))
          end

          expect(info.ipv6_addresses).to eq(expected)
        end
      end

      it 're-raises unexpected ifconfig errors' do
        allow(command_runner).to receive(:call).and_raise(
          os_command_error(exitstatus: 2, command: 'ifconfig', text: 'boom')
        )

        expect { info.ipv6_addresses }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'accepts an explicit interface and timeout for bounded status lookups' do
        expect(command_runner).to receive(:call)
          .with(%w[ifconfig en1], timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "\tinet6 2001:db8::5 prefixlen 64\n"))

        expect(info.ipv6_addresses(iface: 'en1', timeout_in_secs: 0.25)).to eq(['2001:db8::5'])
      end
    end

    describe '#default_interface' do
      it 'extracts default interface from route output' do
        test_cases = [
          ["   interface: en0\n", 'en0'],
          ['   interface: wlan0', 'wlan0'],
          ["   interface: \n", nil],
          ['', nil],
          [os_command_error(exitstatus: 1, command: 'route', text: ''), nil],
        ]

        test_cases.each do |response, expected|
          if response.is_a?(Exception)
            allow(command_runner).to receive(:call).with(%w[route -n get default],
              raise_on_error: false).and_raise(response)
          else
            allow(command_runner).to receive(:call).with(%w[route -n get default],
              raise_on_error: false).and_return(command_result(stdout: response))
          end

          expect(info.default_interface).to eq(expected)
        end
      end

      it 'accepts an explicit timeout for bounded status lookups' do
        expect(command_runner).to receive(:call)
          .with(%w[route -n get default], raise_on_error: false, timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "interface: en1\n"))

        expect(info.default_interface(timeout_in_secs: 0.25)).to eq('en1')
      end
    end

    describe '#mac_address' do
      it 'extracts MAC address from ifconfig output' do
        ifconfig_output = "en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n" \
          "\tether ac:bc:32:b9:a9:9d\n"
        allow(command_runner).to receive(:call).with(%w[ifconfig en0])
          .and_return(command_result(stdout: ifconfig_output))

        expect(info.mac_address).to eq('ac:bc:32:b9:a9:9d')
      end
    end

    describe '#wifi_on?' do
      it 'detects Wi-Fi power from networksetup output' do
        test_cases = [
          ["Wi-Fi Power (en0): On\n", true],
          ["Wi-Fi Power (en0): Off\n", false],
        ]

        test_cases.each do |output, expected|
          allow(command_runner).to receive(:call)
            .with(%w[networksetup -getairportpower en0])
            .and_return(command_result(stdout: output))

          expect(info.wifi_on?).to eq(expected)
        end
      end

      it 'accepts an explicit interface and timeout for bounded status lookups' do
        expect(command_runner).to receive(:call)
          .with(%w[networksetup -getairportpower en1], timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "Wi-Fi Power (en1): On\n"))

        expect(info.wifi_on?(iface: 'en1', timeout_in_secs: 0.25)).to be(true)
      end
    end

    describe '#open_resource' do
      it 'constructs open commands properly' do
        test_cases = [
          'http://example.com',
          'file:///path with spaces/file.txt',
          '/Applications/Safari.app',
        ]

        test_cases.each do |resource|
          expect(command_runner).to receive(:call).with(['open', resource])
          info.open_resource(resource)
        end
      end
    end

    describe '#detect_macos_version' do
      it 'normalizes the sw_vers product version' do
        expect(command_runner).to receive(:call)
          .with(%w[sw_vers -productVersion])
          .and_return(command_result(stdout: "15.6\n"))

        expect(info.detect_macos_version).to eq('15.6')
      end

      it 'passes through an explicit timeout' do
        expect(command_runner).to receive(:call)
          .with(%w[sw_vers -productVersion], timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "14.7.1\n"))

        expect(info.detect_macos_version(timeout_in_secs: 0.25)).to eq('14.7.1')
      end

      it 'returns nil when version detection fails' do
        allow(command_runner).to receive(:call).with(%w[sw_vers -productVersion])
          .and_raise(
            os_command_error(exitstatus: 1, command: 'sw_vers -productVersion', text: 'Command failed')
          )

        expect(info.detect_macos_version).to be_nil
      end

      it 'logs version detection failures when verbose output is enabled' do
        out_stream = StringIO.new
        verbose_info = described_class.new(
          command_runner:          command_runner,
          wifi_interface_provider: -> { wifi_interface },
          out_stream_provider:     -> { out_stream },
          verbosity_provider:      -> { true }
        )
        allow(command_runner).to receive(:call).with(%w[sw_vers -productVersion])
          .and_raise(
            os_command_error(exitstatus: 1, command: 'sw_vers -productVersion', text: 'Command failed')
          )

        expect(verbose_info.detect_macos_version).to be_nil
        expect(out_stream.string).to include('Could not detect macOS version:')
      end
    end
  end
end
