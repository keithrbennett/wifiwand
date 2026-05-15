# frozen_string_literal: true

require 'json'
require_relative '../../../spec_helper'
require_relative '../../../../lib/wifi_wand/models/mac_os/interface_detector'

module WifiWand
  describe MacOsInterfaceDetector do
    subject(:detector) { described_class.new(command_runner: command_runner) }

    let(:command_runner) { double('command_runner') }

    describe '#fetch_hardware_ports' do
      it 'parses networksetup hardware ports into hashes' do
        output = "Hardware Port: Ethernet\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:ff\n\n" \
          "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: 11:22:33:44:55:66\n"
        allow(command_runner).to receive(:call).with(
          %w[networksetup -listallhardwareports],
          timeout_in_secs: 2
        ).and_return(command_result(stdout: output))

        expect(detector.fetch_hardware_ports(timeout_in_secs: 2)).to eq([
          { name: 'Ethernet', device: 'en1', ethernet_address: 'aa:bb:cc:dd:ee:ff' },
          { name: 'Wi-Fi', device: 'en0', ethernet_address: '11:22:33:44:55:66' },
        ])
      end
    end

    describe '#wifi_service_name_from_ports' do
      it 'selects common WiFi service names by pattern' do
        ports = [
          { name: 'Ethernet', device: 'en1' },
          { name: 'AirPort', device: 'en0' },
        ]

        expect(detector.wifi_service_name_from_ports(ports)).to eq('AirPort')
      end

      it 'uses the known interface when the service has a nonstandard name' do
        ports = [
          { name: 'USB Adapter', device: 'en7' },
          { name: 'Ethernet', device: 'en1' },
        ]

        expect(detector.wifi_service_name_from_ports(ports, known_interface: 'en7')).to eq('USB Adapter')
      end

      it 'falls back to Wi-Fi when no hardware port identifies WiFi' do
        ports = [{ name: 'Ethernet', device: 'en1' }]

        expect(detector.wifi_service_name_from_ports(ports)).to eq('Wi-Fi')
      end
    end

    describe '#wifi_interface_using_networksetup' do
      it 'returns both the interface and service name learned from networksetup' do
        output = "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: 11:22:33:44:55:66\n"
        allow(command_runner).to receive(:call).and_return(command_result(stdout: output))

        result = detector.wifi_interface_using_networksetup

        expect(result.interface).to eq('en0')
        expect(result.service_name).to eq('Wi-Fi')
      end

      it 'returns the fallback service name without an interface when WiFi hardware is missing' do
        output = "Hardware Port: Ethernet\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:ff\n"
        allow(command_runner).to receive(:call).and_return(command_result(stdout: output))

        result = detector.wifi_interface_using_networksetup

        expect(result.interface).to be_nil
        expect(result.service_name).to eq('Wi-Fi')
      end
    end

    describe '#probe' do
      let(:profiler_json) do
        {
          'SPNetworkDataType' => [
            { '_name' => 'Ethernet', 'interface' => 'en1' },
            { '_name' => 'Wi-Fi', 'interface' => 'en0' },
          ],
        }.to_json
      end

      it 'tries networksetup first and falls back to system_profiler' do
        expect(command_runner).to receive(:call).with(
          %w[networksetup -listallhardwareports],
          timeout_in_secs: nil
        ).ordered.and_return(command_result(stdout: "Hardware Port: Ethernet\nDevice: en1\n"))
        expect(command_runner).to receive(:call).with(
          described_class::SYSTEM_PROFILER_NETWORK_ARGS,
          raise_on_error:  true,
          timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
        ).ordered.and_return(command_result(stdout: profiler_json))

        result = detector.probe

        expect(result.interface).to eq('en0')
        expect(result.service_name).to eq('Wi-Fi')
      end

      it 'uses a known service name when parsing system_profiler fallback data' do
        profiler_json = {
          'SPNetworkDataType' => [
            { '_name' => 'Wi-Fi', 'interface' => 'en0' },
            { '_name' => 'Corp WLAN', 'interface' => 'en7' },
          ],
        }.to_json
        allow(command_runner).to receive(:call)
          .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
          .and_raise(os_command_error(exitstatus: 1, command: 'networksetup', text: 'boom'))
        allow(command_runner).to receive(:call)
          .with(
            described_class::SYSTEM_PROFILER_NETWORK_ARGS,
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          )
          .and_return(command_result(stdout: profiler_json))

        result = detector.probe(known_service_name: 'Corp WLAN')

        expect(result.interface).to eq('en7')
        expect(result.service_name).to eq('Corp WLAN')
      end

      it 'returns an empty result when neither source reports WiFi hardware' do
        allow(command_runner).to receive(:call)
          .with(%w[networksetup -listallhardwareports], timeout_in_secs: nil)
          .and_return(command_result(stdout: "Hardware Port: Ethernet\nDevice: en1\n"))
        allow(command_runner).to receive(:call)
          .with(
            described_class::SYSTEM_PROFILER_NETWORK_ARGS,
            raise_on_error:  true,
            timeout_in_secs: described_class::SYSTEM_PROFILER_TIMEOUT_SECONDS
          )
          .and_return(command_result(stdout: { 'SPNetworkDataType' => [] }.to_json))

        result = detector.probe

        expect(result.interface).to be_nil
        expect(result.service_name).to be_nil
      end
    end

    describe '#detect_wifi_interface_from_profiler_networks' do
      it 'falls back to a known interface when no known service name is available' do
        networks = [
          { '_name' => 'Ethernet', 'interface' => 'en1' },
          { '_name' => 'USB Adapter', 'interface' => 'en7' },
          { '_name' => 'Wi-Fi', 'interface' => 'en0' },
        ]

        result = detector.detect_wifi_interface_from_profiler_networks(
          networks,
          known_interface: 'en7'
        )

        expect(result.interface).to eq('en7')
        expect(result.service_name).to eq('USB Adapter')
      end
    end
  end
end
