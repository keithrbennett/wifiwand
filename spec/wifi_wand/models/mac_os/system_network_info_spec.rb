# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/mac_os/system_network_info'

module WifiWand
  describe MacOsSystemNetworkInfo do
    subject(:info) do
      described_class.new(
        command_runner:      command_runner,
        wifi_interface_proc: -> { wifi_interface }
      )
    end

    let(:command_runner) { double('command_runner') }
    let(:wifi_interface) { 'en0' }

    describe '#ip_address' do
      it 'handles different ipconfig responses' do
        test_cases = [
          ["192.168.1.100\n", '192.168.1.100'],
          ['10.0.0.5', '10.0.0.5'],
          ['', nil],
          [os_command_error(exitstatus: 1, command: 'ipconfig', text: ''), nil],
        ]

        test_cases.each do |response, expected|
          if response.is_a?(Exception)
            allow(command_runner).to receive(:call).and_raise(response)
          else
            allow(command_runner).to receive(:call).and_return(command_result(stdout: response))
          end

          expect(info.ip_address).to eq(expected)
        end
      end

      it 're-raises unexpected ipconfig errors' do
        allow(command_runner).to receive(:call).and_raise(
          os_command_error(exitstatus: 2, command: 'ipconfig', text: 'boom')
        )

        expect { info.ip_address }.to raise_error(WifiWand::CommandExecutor::OsCommandError)
      end

      it 'accepts an explicit interface and timeout for bounded status lookups' do
        expect(command_runner).to receive(:call)
          .with(%w[ipconfig getifaddr en1], timeout_in_secs: 0.25)
          .and_return(command_result(stdout: "192.168.1.5\n"))

        expect(info.ip_address(iface: 'en1', timeout_in_secs: 0.25)).to eq('192.168.1.5')
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
  end
end
