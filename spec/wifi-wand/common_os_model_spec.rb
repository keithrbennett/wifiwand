require_relative '../../lib/wifi-wand/operating_systems'

describe 'Common WiFi Model Behavior (All OS)' do
  
  # Automatically instantiate the correct model for the current OS
  subject do
    os_detector = WifiWand::OperatingSystems.new
    current_os = os_detector.current_os
    current_os.create_model(OpenStruct.new(verbose: false))
  end

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
      subject.wifi_off if subject.wifi_on?
      expect(subject.wifi_on?).to be(false)
      
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
    end

    it 'does nothing when wifi is already on' do
      subject.wifi_on unless subject.wifi_on?
      expect(subject.wifi_on?).to be(true)
      
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
    end
  end

  describe '#wifi_off', :disruptive do
    it 'can turn wifi off when it is on' do
      subject.wifi_on unless subject.wifi_on?
      expect(subject.wifi_on?).to be(true)
      
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
    end

    it 'does nothing when wifi is already off' do
      subject.wifi_off if subject.wifi_on?
      expect(subject.wifi_on?).to be(false)
      
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
    end
  end

  describe '#cycle_network', :disruptive do
    it 'can turn wifi off and on, preserving network selection' do
      # Note: This test may not preserve network connection in all cases
      # but should verify the cycle completes without error
      subject.wifi_on unless subject.wifi_on?
      expect { subject.cycle_network }.not_to raise_error
      expect(subject.wifi_on?).to be(true)
    end
  end

  describe '#available_network_names', :disruptive do
    it 'can list available networks' do
      subject.wifi_on unless subject.wifi_on?
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
      subject.wifi_on unless subject.wifi_on?
      
      # If we're not connected to any network, we can't test this scenario
      if subject.connected_network_name.nil?
        skip 'No network connection available to test connected disconnect'
      end
      
      # Test that disconnect doesn't raise error when connected
      expect { subject.disconnect }.not_to raise_error
    end
  end

  # The following tests run commands and verify they complete without error,
  # testing both wifi on and wifi off states
  shared_examples 'interface commands complete without error' do |wifi_starts_on|

    it 'can determine if connected to Internet' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.connected_to_internet?
    end

    it 'can get wifi interface' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      result = subject.wifi_interface
      expect(result).to be_a(String).or(be_nil)
    end

    it 'can get wifi info' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      result = subject.wifi_info
      expect(result).to be_a(Hash)
    end

    it 'can list preferred networks' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      result = subject.preferred_networks
      expect(result).to be_a(Array)
      expect(result).to all(be_a(String))
    end

    it 'can check wifi status' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      result = subject.wifi_on?
      expect([true, false]).to include(result)
    end

    it 'can query connected network name' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      name = subject.connected_network_name
      unless subject.wifi_on?
        expect(name).to be_nil
      end
    end

    
  end

  context 'wifi starts on' do
    include_examples 'interface commands complete without error', true
  end

  context 'wifi starts off' do
    include_examples 'interface commands complete without error', false
  end

end