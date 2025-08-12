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

  describe '#disconnect', :modifies_system do
    it 'completes without raising an error' do
      # Tagged as :modifies_system to exclude by default since it may disrupt network
      # Run with: bundle exec rspec --tag modifies_system
      subject.disconnect
    end
  end

end