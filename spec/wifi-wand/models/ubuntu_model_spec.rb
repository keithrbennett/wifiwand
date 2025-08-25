require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/models/ubuntu_model'

module WifiWand

describe UbuntuModel, :os_ubuntu do
  

  subject { create_ubuntu_test_model }


  # System-modifying tests (will change wifi state)
  context 'system-modifying operations', :disruptive do

    describe '#wifi_on' do
      it 'turns wifi on when it is off' do
        subject.wifi_off
        expect(subject.wifi_on?).to be(false)
        
        subject.wifi_on
        expect(subject.wifi_on?).to be(true)
      end
    end

    describe '#wifi_off' do
      it 'turns wifi off when it is on' do
        subject.wifi_on
        expect(subject.wifi_on?).to be(true)
        
        subject.wifi_off
        expect(subject.wifi_on?).to be(false)
      end
    end

    describe '#disconnect' do
      it 'disconnects from current network' do
        # Can disconnect even when not connected to a network
        expect { subject.disconnect }.not_to raise_error
      end
    end

    describe '#remove_preferred_network' do
      it 'removes a preferred network' do
        networks = subject.preferred_networks
        if networks.any?
          network = networks.first
          expect { subject.remove_preferred_network(network) }.not_to raise_error
        else
          pending 'No preferred networks available to remove'
        end
      end

      it 'handles removal of non-existent network' do
        expect { subject.remove_preferred_network('non_existent_network_123') }.not_to raise_error
      end
    end

    describe '#set_nameservers' do
      let(:valid_nameservers) { ['8.8.8.8', '8.8.4.4'] }
      
      it 'sets valid nameservers' do
        subject.wifi_on
        result = subject.set_nameservers(valid_nameservers)
        expect(result).to eq(valid_nameservers)
      end

      it 'clears nameservers with :clear' do
        subject.wifi_on
        result = subject.set_nameservers(:clear)
        expect(result).to eq(:clear)
      end

      it 'raises error for invalid IP addresses' do
        invalid_nameservers = ['invalid.ip', '256.256.256.256']
        expect { subject.set_nameservers(invalid_nameservers) }.to raise_error(WifiWand::InvalidIPAddressError)
      end
    end

  end

  # Network connection tests (highest risk)
  context 'network connection operations', :disruptive do

    describe '#_connect' do
      it 'raises error for non-existent network' do
        expect { subject._connect('non_existent_network_123') }.to raise_error(WifiWand::NetworkNotFoundError)
      end
    end

  end

end

end