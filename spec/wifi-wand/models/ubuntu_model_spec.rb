require_relative '../../../lib/wifi-wand/models/ubuntu_model'

module WifiWand

describe UbuntuModel, :os_ubuntu do

  subject { UbuntuModel.new(OpenStruct.new(verbose: false)) }

  # Read-only tests (no system state changes)
  context 'read-only operations', :read_only do

    describe '#detect_wifi_interface' do
      it 'returns a wifi interface name' do
        # This should complete without error, even if no wifi interface exists
        result = subject.detect_wifi_interface
        expect(result).to be_a(String).or(be_nil)
      end
    end

    describe '#is_wifi_interface?' do
      it 'returns boolean for valid interface' do
        interface = subject.detect_wifi_interface
        if interface
          result = subject.is_wifi_interface?(interface)
          expect([true, false]).to include(result)
        else
          # Skip test if no wifi interface detected
          pending 'No wifi interface available'
        end
      end

      it 'returns boolean for interface check' do
        # This test just verifies the method returns a boolean
        # The actual result depends on the system configuration
        result = subject.is_wifi_interface?('nonexistent_interface_12345')
        expect([true, false]).to include(result)
      end
    end

    describe '#wifi_on?' do
      it 'returns boolean indicating wifi status' do
        result = subject.wifi_on?
        expect([true, false]).to include(result)
      end
    end

    describe '#available_network_names' do
      it 'returns array or nil when wifi is off', :skip_disruptive do
        # Skip this test to avoid turning off WiFi
        skip 'Test skipped to avoid WiFi disruption'
      end

      it 'returns array of network names when wifi is on', :requires_wifi_on do
        # Check current state without modifying it
        if subject.wifi_on?
          result = subject.available_network_names
          expect(result).to be_a(Array).or(be_nil)
          if result
            expect(result).to all(be_a(String))
          end
        else
          skip 'WiFi is currently off'
        end
      end

      it 'returns unique network names when wifi is on', :requires_wifi_on do
        # Check that duplicate SSIDs are removed (strongest signal kept)
        if subject.wifi_on?
          result = subject.available_network_names
          expect(result).to be_a(Array).or(be_nil)
          if result
            expect(result.uniq).to eq(result)  # Should be unique
          end
        else
          skip 'WiFi is currently off'
        end
      end
    end

    describe '#connected_network_name' do
      it 'returns string or nil when wifi is off', :skip_disruptive do
        # Skip this test to avoid turning off WiFi
        skip 'Test skipped to avoid WiFi disruption'
      end

      it 'returns string or nil when wifi is on', :requires_wifi_on do
        # Check current state without modifying it
        if subject.wifi_on?
          result = subject.connected_network_name
          expect(result).to be_a(String).or(be_nil)
        else
          skip 'WiFi is currently off'
        end
      end
    end

    describe '#preferred_networks' do
      it 'returns array of preferred network names' do
        result = subject.preferred_networks
        expect(result).to be_a(Array)
        expect(result).to all(be_a(String))
      end
    end

    describe '#ip_address' do
      it 'returns string or nil when wifi is off' do
        # Don't actually turn off wifi to avoid disconnecting
        result = subject.ip_address
        expect(result).to be_a(String).or(be_nil)
        if result
          # Allow for multiple IP addresses (one per line)
          expect(result).to match(/\A(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(\s|\n|$))+/)
        end
      end

      it 'returns string or nil when wifi is on', :requires_wifi_on do
        # Don't force wifi on to avoid disrupting network
        result = subject.ip_address
        expect(result).to be_a(String).or(be_nil)
        if result
          # Allow for multiple IP addresses (one per line)
          expect(result).to match(/\A(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(\s|\n|$))+/)
        end
      end
    end

    describe '#mac_address' do
      it 'returns string or nil when wifi interface is available' do
        interface = subject.detect_wifi_interface
        if interface
          result = subject.mac_address
          if result
            # Handle multiple MAC addresses (one per line)
            result.each_line do |line|
              expect(line.strip).to match(/\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/).or(be_empty)
            end
          end
        else
          pending 'No wifi interface available'
        end
      end
    end

    describe '#nameservers' do
      it 'returns array of nameserver addresses' do
        result = subject.nameservers
        expect(result).to be_a(Array).or(be_nil)
        if result && !result.empty?
          expect(result).to all(match(/\A(\d{1,3}\.){3}\d{1,3}\z/))
        end
      end
    end

    
    describe '#os_level_preferred_network_password' do
      it 'returns string or nil for existing network' do
        networks = subject.preferred_networks
        if networks.any?
          result = subject.os_level_preferred_network_password(networks.first)
          expect(result).to be_a(String).or(be_nil)
        else
          pending 'No preferred networks available'
        end
      end

      it 'returns nil for non-existent network' do
        result = subject.os_level_preferred_network_password('non_existent_network_123')
        expect(result).to be_nil
      end
    end

  end

  # System-modifying tests (will change wifi state)
  context 'system-modifying operations', :disruptive do

    describe '#wifi_on' do
      it 'turns wifi on when it is off' do
        subject.wifi_off
        expect(subject.wifi_on?).to be(false)
        
        subject.wifi_on
        expect(subject.wifi_on?).to be(true)
      end

      it 'does nothing when wifi is already on' do
        subject.wifi_on
        expect(subject.wifi_on?).to be(true)
        
        expect { subject.wifi_on }.not_to raise_error
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

      it 'does nothing when wifi is already off' do
        subject.wifi_off
        expect(subject.wifi_on?).to be(false)
        
        expect { subject.wifi_off }.not_to raise_error
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
        expect { subject.set_nameservers(invalid_nameservers) }.to raise_error(WifiWand::Error)
      end
    end

  end

  # Network connection tests (highest risk)
  context 'network connection operations', :disruptive do

    describe '#_connect' do
      it 'raises error for non-existent network' do
        expect { subject._connect('non_existent_network_123') }.to raise_error(WifiWand::Error)
      end
    end

  end

end

end