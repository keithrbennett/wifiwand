require 'spec_helper'
require 'wifi-wand/models/mac_os_model'
require 'wifi-wand/models/ubuntu_model'

RSpec.describe 'MAC Address' do
  let(:mac_os_model) { WifiWand::MacOsModel.new(OpenStruct.new(verbose: false)) }
  let(:ubuntu_model) { WifiWand::UbuntuModel.new(OpenStruct.new(verbose: false)) }

  before do
    allow(mac_os_model).to receive(:wifi_interface).and_return('en0')
    allow(ubuntu_model).to receive(:wifi_interface).and_return('wlan0')
  end

  describe '#mac_address' do
    context 'when getting the MAC address' do
      it 'returns the current MAC address for macOS' do
        allow(mac_os_model).to receive(:run_os_command).with("ifconfig en0 | awk '/ether/{print $2}'").and_return('aa:bb:cc:dd:ee:ff')
        expect(mac_os_model.mac_address).to eq('aa:bb:cc:dd:ee:ff')
      end

      it 'returns the current MAC address for Ubuntu' do
        allow(ubuntu_model).to receive(:run_os_command).with("ip link show wlan0 | grep ether | awk '{print $2}'", false).and_return('aa:bb:cc:dd:ee:ff')
        expect(ubuntu_model.mac_address).to eq('aa:bb:cc:dd:ee:ff')
      end
    end

    context 'when setting the MAC address' do
      it 'sets the MAC address for macOS' do
        expect(mac_os_model).to receive(:run_os_command).with("sudo ifconfig en0 ether 11:22:33:44:55:66")
        expect(mac_os_model).to receive(:run_os_command).with("ifconfig en0 | awk '/ether/{print $2}'").and_return('11:22:33:44:55:66')
        mac_os_model.mac_address('11:22:33:44:55:66')
      end

      it 'sets the MAC address for Ubuntu' do
        expect(ubuntu_model).to receive(:run_os_command).with("sudo ip link set dev wlan0 down")
        expect(ubuntu_model).to receive(:run_os_command).with("sudo ip link set dev wlan0 address 11:22:33:44:55:66")
        expect(ubuntu_model).to receive(:run_os_command).with("sudo ip link set dev wlan0 up")
        expect(ubuntu_model).to receive(:run_os_command).with("ip link show wlan0 | grep ether | awk '{print $2}'", false).and_return('11:22:33:44:55:66')
        ubuntu_model.mac_address('11:22:33:44:55:66')
      end

      it 'raises an error for an invalid MAC address' do
        expect { mac_os_model.mac_address('invalid-mac') }.to raise_error(WifiWand::InvalidMacAddressError)
        expect { ubuntu_model.mac_address('invalid-mac') }.to raise_error(WifiWand::InvalidMacAddressError)
      end
    end
  end
end
