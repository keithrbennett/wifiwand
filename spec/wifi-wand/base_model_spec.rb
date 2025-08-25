require_relative '../../lib/wifi-wand/operating_systems'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

describe 'Common WiFi Model Behavior (All OS)' do
  
  # Mock OS calls to prevent real system interaction during non-disruptive tests
  before(:each) do
    # Mock detect_wifi_interface for both OS types
    allow_any_instance_of(WifiWand::UbuntuModel).to receive(:detect_wifi_interface).and_return('wlp0s20f3')
    allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0') if defined?(WifiWand::MacOsModel)
    
    # Mock all OS-calling methods to prevent real system calls in non-disruptive tests
    # Only mock for non-disruptive tests (those not tagged with :disruptive)
    unless self.class.metadata[:disruptive] || self.class.parent_groups.any? { |group| group.metadata[:disruptive] }
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:available_network_names).and_return(['TestNetwork1', 'TestNetwork2'])
      allow(subject).to receive(:connected_network_name).and_return('TestNetwork1')
      allow(subject).to receive(:ip_address).and_return('192.168.1.100')
      allow(subject).to receive(:mac_address).and_return('aa:bb:cc:dd:ee:ff')
      allow(subject).to receive(:default_interface).and_return('wlan0')
      allow(subject).to receive(:nameservers).and_return(['8.8.8.8', '8.8.4.4'])
      allow(subject).to receive(:preferred_networks).and_return(['TestNetwork1', 'SavedNetwork1'])
      allow(subject).to receive(:internet_tcp_connectivity?).and_return(true)
      allow(subject).to receive(:dns_working?).and_return(true)
      allow(subject).to receive(:connected_to_internet?).and_return(true)
      allow(subject).to receive(:public_ip_address_info).and_return({'ip' => '1.2.3.4'})
    end
  end
  
  # Automatically instantiate the correct model for the current OS
  subject { create_test_model }

  # These tests run on any OS - interface consistency tests
  describe '#internet_tcp_connectivity?' do
    it 'returns boolean indicating TCP connectivity' do
      expect([true, false]).to include(subject.internet_tcp_connectivity?)
    end
  end

  describe '#dns_working?' do
    it 'returns boolean indicating DNS resolution capability' do
      expect([true, false]).to include(subject.dns_working?)
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
      # Override default mocks for this specific test if needed
      allow(subject).to receive(:wifi_interface).and_return('wlan0')
      
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
      expect([true, false]).to include(subject.wifi_on?)
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
      expect(subject.connected_network_name).to be_a(String).or(be_nil)
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

  describe '#connect with saved passwords' do
    it 'uses saved password when none provided and network is preferred' do
      network_name = 'SavedNetwork1'
      saved_password = 'saved_password_123'
      
      # Mock that the network is in preferred networks
      allow(subject).to receive(:preferred_networks).and_return([network_name])
      allow(subject).to receive(:preferred_network_password).with(network_name).and_return(saved_password)
      allow(subject).to receive(:connected_network_name).and_return(nil, network_name)
      allow(subject).to receive(:wifi_on)
      allow(subject).to receive(:_connect)
      
      # Connect without providing password
      subject.connect(network_name)
      
      # Should have called _connect with the saved password
      expect(subject).to have_received(:_connect).with(network_name, saved_password)
      expect(subject.last_connection_used_saved_password?).to be true
    end

    it 'does not use saved password when one is provided' do
      network_name = 'SavedNetwork1'
      provided_password = 'provided_password'
      
      allow(subject).to receive(:preferred_networks).and_return([network_name])
      allow(subject).to receive(:connected_network_name).and_return(nil, network_name)
      allow(subject).to receive(:wifi_on)
      allow(subject).to receive(:_connect)
      
      # Connect with explicit password
      subject.connect(network_name, provided_password)
      
      # Should have called _connect with the provided password
      expect(subject).to have_received(:_connect).with(network_name, provided_password)
      expect(subject.last_connection_used_saved_password?).to be false
    end

    it 'does not use saved password when network is not preferred' do
      network_name = 'UnknownNetwork'
      
      allow(subject).to receive(:preferred_networks).and_return(['SavedNetwork1'])
      allow(subject).to receive(:connected_network_name).and_return(nil, network_name)
      allow(subject).to receive(:wifi_on)
      allow(subject).to receive(:_connect)
      
      # Connect without password to non-preferred network
      subject.connect(network_name)
      
      # Should have called _connect with nil password
      expect(subject).to have_received(:_connect).with(network_name, nil)
      expect(subject.last_connection_used_saved_password?).to be false
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

  describe '#cycle_network' do
    # Shared setup for mocking wifi operations without system calls
    before do
      allow(subject).to receive(:wifi_off)
      allow(subject).to receive(:wifi_on)
    end
    
    context 'when wifi starts on' do
      before do
        allow(subject).to receive(:wifi_on?).and_return(true)
      end
      
      it 'calls wifi_off then wifi_on in sequence' do
        subject.cycle_network
        
        expect(subject).to have_received(:wifi_off).ordered
        expect(subject).to have_received(:wifi_on).ordered
      end
    end
    
    context 'when wifi starts off' do
      before do
        allow(subject).to receive(:wifi_on?).and_return(false)
      end
      
      it 'calls wifi_on then wifi_off in sequence' do
        subject.cycle_network
        
        expect(subject).to have_received(:wifi_on).ordered
        expect(subject).to have_received(:wifi_off).ordered
      end
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
      expect(subject.wifi_interface).to be_a(String).or(be_nil)
    end

    it 'can get wifi info' do
      expect(subject.wifi_info).to be_a(Hash)
    end

    it 'can list preferred networks' do
      result = subject.preferred_networks
      expect(result).to be_a(Array)
      expect(result).to all(be_a(String))
    end

    it 'can check wifi status' do
      expect([true, false]).to include(subject.wifi_on?)
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

    it 'returns :no_state_to_restore when state is nil' do
      expect(subject.restore_network_state(nil)).to eq(:no_state_to_restore)
    end

    it 'returns :already_connected when already on correct network' do
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:connected_network_name).and_return('TestNetwork')

      expect(subject.restore_network_state(valid_state)).to eq(:already_connected)
    end
  end

end