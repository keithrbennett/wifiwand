require_relative '../../lib/wifi-wand/operating_systems'

describe 'Common WiFi Model Behavior (All OS)' do
  
  # Automatically instantiate the correct model for the current OS
  subject { create_test_model }

  # These tests run on any OS - interface consistency tests
  describe '#internet_tcp_connectivity?' do
    it 'returns boolean indicating TCP connectivity' do
      result = subject.internet_tcp_connectivity?
      expect([true, false]).to include(result)
    end
  end

  describe '#dns_working?' do
    it 'returns boolean indicating DNS resolution capability' do
      result = subject.dns_working?
      expect([true, false]).to include(result)
    end
  end

  describe '#default_interface' do
    it 'returns string or nil for default route interface' do
      result = subject.default_interface
      expect(result).to be_a(String).or(be_nil)
      if result
        expect(result).to match(/\A[a-zA-Z0-9]+\z/)
      end
    end
  end

  describe '#wifi_info' do
    it 'returns hash with consistent structure across all OSes' do
      result = subject.wifi_info
      expect(result).to be_a(Hash)
      
      # All OSes must provide these fields with consistent types
      expect(result).to include(
        'wifi_on', 'internet_tcp_connectivity', 'dns_working', 'internet_on', 
        'interface', 'default_interface', 'network', 'ip_address', 'mac_address',
        'nameservers', 'timestamp'
      )
      
      expect([true, false]).to include(result['wifi_on'])
      expect([true, false]).to include(result['internet_tcp_connectivity'])
      expect([true, false]).to include(result['dns_working'])
      expect([true, false]).to include(result['internet_on'])
      expect(result['timestamp']).to be_a(Time)
    end
  end

  describe '#wifi_on?' do
    it 'returns boolean indicating wifi status' do
      result = subject.wifi_on?
      expect([true, false]).to include(result)
    end
  end

  describe '#available_network_names' do
    it 'returns array or nil for available networks' do
      result = subject.available_network_names
      expect(result).to be_a(Array).or(be_nil)
      if result
        expect(result).to all(be_a(String))
      end
    end
  end

  describe '#connected_network_name' do
    it 'returns string or nil for connected network' do
      result = subject.connected_network_name
      expect(result).to be_a(String).or(be_nil)
    end
  end

  describe '#ip_address' do
    it 'returns string or nil for IP address' do
      result = subject.ip_address
      expect(result).to be_a(String).or(be_nil)
      if result
        expect(result).to match(/\A(\d{1,3}\.){3}\d{1,3}\z/)
      end
    end
  end

  describe '#mac_address' do
    it 'returns string or nil for MAC address' do
      result = subject.mac_address
      expect(result).to be_a(String).or(be_nil)
      if result
        expect(result).to match(/\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/)
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

  describe '#preferred_networks' do
    it 'returns array of preferred network names' do
      result = subject.preferred_networks
      expect(result).to be_a(Array)
      expect(result).to all(be_a(String))
    end
  end

  describe '#disconnect', :disruptive do
    it 'completes without raising an error' do
      # Tagged as :modifies_system to exclude by default since it may disrupt network
      # Run with: bundle exec rspec --tag modifies_system
      subject.disconnect
    end
  end

  describe '#wifi_on', :disruptive do
    it 'can turn wifi on when it is off' do
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
      
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
    end

    it 'does nothing when wifi is already on' do
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
      
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
    end
  end

  describe '#wifi_off', :disruptive do
    it 'can turn wifi off when it is on' do
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
      
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
    end

    it 'does nothing when wifi is already off' do
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
      
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
    end
  end

  describe '#cycle_network', :disruptive do
    it 'can turn wifi off and on, preserving network selection' do
      # Note: This test may not preserve network connection in all cases
      # but should verify the cycle completes without error
      subject.wifi_on
      expect { subject.cycle_network }.not_to raise_error
      expect(subject.wifi_on?).to be(true)
    end
  end

  describe '#available_network_names', :disruptive do
    it 'can list available networks' do
      subject.wifi_on
      result = subject.available_network_names
      expect(result).to be_a(Array).or(be_nil)
      if result
        expect(result).to all(be_a(String))
      end
    end
  end

  describe '#disconnect graceful handling', :disruptive do
    it 'handles disconnect gracefully when already disconnected' do
      # Ensure we start in a known state - disconnected
      if subject.connected_network_name
        subject.disconnect
      end
      
      # Now test that calling disconnect on already-disconnected state doesn't raise error
      expect { subject.disconnect }.not_to raise_error
    end
    
    it 'handles disconnect gracefully when connected' do
      # Ensure we're connected to a network first
      subject.wifi_on
      
      # If we're not connected to any network, we can't test this scenario
      if subject.connected_network_name.nil?
        skip 'No network connection available to test connected disconnect'
      end
      
      original_network = subject.connected_network_name
      
      # Test that disconnect doesn't raise error when connected
      expect { subject.disconnect }.not_to raise_error
      
      # Verify we're disconnected
      expect(subject.connected_network_name).to be_nil
    end
  end

  # The following tests run commands and verify they complete without error,
  # testing both wifi on and wifi off states
  shared_examples 'interface commands complete without error' do |wifi_starts_on|

    before(:each) do
      # Only set wifi state in disruptive contexts
      if self.class.metadata[:disruptive]
        wifi_starts_on ? subject.wifi_on : subject.wifi_off
      end
    end

    it 'can determine if connected to Internet' do
      subject.connected_to_internet?
    end

    it 'can get wifi interface' do
      result = subject.wifi_interface
      expect(result).to be_a(String).or(be_nil)
    end

    it 'can get wifi info' do
      result = subject.wifi_info
      expect(result).to be_a(Hash)
    end

    it 'can list preferred networks' do
      result = subject.preferred_networks
      expect(result).to be_a(Array)
      expect(result).to all(be_a(String))
    end

    it 'can check wifi status' do
      result = subject.wifi_on?
      expect([true, false]).to include(result)
    end

    it 'can query connected network name' do
      name = subject.connected_network_name
      unless subject.wifi_on?
        expect(name).to be_nil
      end
    end

    
  end

  # Check current wifi state and create appropriate contexts
  let(:current_wifi_on) { subject.wifi_on? }

  # Non-disruptive context - only runs when wifi is already on
  context 'wifi starts on', :disruptive => false do
    before(:each) do
      skip "Wifi is not currently on" unless current_wifi_on
    end

    include_examples 'interface commands complete without error', true
  end

  # Non-disruptive context - only runs when wifi is already off  
  context 'wifi starts off', :disruptive => false do
    before(:each) do
      skip "Wifi is currently on" if current_wifi_on
    end

    include_examples 'interface commands complete without error', false
  end

  # Disruptive contexts - only run with --tag disruptive flag
  context 'wifi starts on (disruptive)', :disruptive do
    include_examples 'interface commands complete without error', true
  end

  context 'wifi starts off (disruptive)', :disruptive do
    include_examples 'interface commands complete without error', false
  end

  describe '#restore_network_state' do
    let(:valid_state) do
      {
        wifi_enabled: true,
        network_name: 'TestNetwork',
        network_password: 'testpass',
        interface: 'wlan0'
      }
    end

    context 'with fail_silently: false' do
      it 'raises exceptions on wifi operation failures' do
        allow(subject).to receive(:wifi_on?).and_return(false)
        allow(subject).to receive(:wifi_on).and_raise(StandardError.new('WiFi hardware error'))

        expect {
          subject.restore_network_state(valid_state, fail_silently: false)
        }.to raise_error(StandardError, 'WiFi hardware error')
      end

      it 'raises exceptions on connection failures' do
        allow(subject).to receive(:wifi_on?).and_return(true)
        allow(subject).to receive(:connected_network_name).and_return('OtherNetwork')
        allow(subject).to receive(:preferred_network_password).and_return('testpass')
        allow(subject).to receive(:connect).and_raise(StandardError.new('Network unavailable'))

        expect {
          subject.restore_network_state(valid_state, fail_silently: false)
        }.to raise_error(StandardError, 'Network unavailable')
      end
    end

    context 'with fail_silently: true' do
      it 'swallows wifi operation failures and logs to stderr' do
        allow(subject).to receive(:wifi_on?).and_return(false)
        allow(subject).to receive(:wifi_on).and_raise(StandardError.new('WiFi hardware error'))

        expect($stderr).to receive(:puts).with('Warning: Could not restore network state: WiFi hardware error')
        expect($stderr).to receive(:puts).with('You may need to manually reconnect to: TestNetwork')

        expect {
          subject.restore_network_state(valid_state, fail_silently: true)
        }.not_to raise_error
      end

      it 'swallows connection failures and logs to stderr' do
        allow(subject).to receive(:wifi_on?).and_return(true)
        allow(subject).to receive(:connected_network_name).and_return('OtherNetwork')
        allow(subject).to receive(:preferred_network_password).and_return('testpass')
        allow(subject).to receive(:connect).and_raise(StandardError.new('Network unavailable'))
        allow(subject).to receive(:till)

        expect($stderr).to receive(:puts).with('Warning: Could not restore network state: Network unavailable')
        expect($stderr).to receive(:puts).with('You may need to manually reconnect to: TestNetwork')

        expect {
          subject.restore_network_state(valid_state, fail_silently: true)
        }.not_to raise_error
      end
    end

    it 'returns :no_state_to_restore when state is nil' do
      result = subject.restore_network_state(nil)
      expect(result).to eq(:no_state_to_restore)
    end

    it 'returns :already_connected when already on correct network' do
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:connected_network_name).and_return('TestNetwork')

      result = subject.restore_network_state(valid_state)
      expect(result).to eq(:already_connected)
    end
  end

end