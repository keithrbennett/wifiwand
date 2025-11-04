# frozen_string_literal: true

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
    # Check both example-level and group-level metadata for :disruptive tag
    # Use RSpec.current_example to get the current running example
    unless is_disruptive?
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
      # Don't mock connected_to_internet? globally - let tests override it when needed
      allow(subject).to receive(:fast_connectivity?).and_return(true)
      allow(subject).to receive(:public_ip_address_info).and_return({'ip' => '1.2.3.4'})
      
      # Also mock the underlying NetworkConnectivityTester to prevent real network calls
      # Don't mock connected_to_internet? - let it use the passed parameters
      allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:tcp_connectivity?).and_return(true)
      allow_any_instance_of(WifiWand::NetworkConnectivityTester).to receive(:dns_working?).and_return(true)
      
      # Mock low-level OS command execution to prevent real system calls
      # but allow higher-level methods to be called for testing
      allow(subject).to receive(:run_os_command).and_return(command_result(stdout: ''))
      allow(subject).to receive(:till).and_return(nil)
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
      expect(subject.default_interface).to be_nil_or_a_string_matching(/\A[a-zA-Z0-9]+\z/)
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
      expect(subject.available_network_names).to be_nil_or_an_array_of_strings
    end
  end

  describe '#connected_network_name' do
    it 'returns string or nil for connected network' do
      expect(subject.connected_network_name).to be_nil_or_a_string
    end
  end

  describe '#ip_address' do
    it 'returns string or nil for IP address' do
      expect(subject.ip_address).to be_nil_or_a_string_matching(/\A(\d{1,3}\.){3}\d{1,3}\z/)
    end
  end

  describe '#mac_address' do
    it 'returns string or nil for MAC address' do
      expect(subject.mac_address).to be_nil_or_a_string_matching(/\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/)
    end
  end

  describe '#nameservers' do
    it 'returns array of nameserver addresses' do
      expect(subject.nameservers).to be_nil_or_an_array_of_ip_addresses
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
    it 'disconnects from network and handles subsequent calls gracefully', :needs_sudo_access => (WifiWand::OperatingSystems.current_id == :mac) do
      subject.wifi_on
      
      # Ensure we\'re connected first (may need to connect to a network if not already)
      if subject.connected_network_name.nil?
        skip "No network connection available for disconnect test"
      end
      
      # Test disconnect works
      subject.disconnect
      expect(subject.connected_network_name).to be_nil
      
      # Test calling disconnect again doesn\'t raise error
      expect { subject.disconnect }.not_to raise_error
    end
  end

  describe '#wifi_on' do
    it 'does nothing when wifi is already on' do
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:run_os_command)
      allow(subject).to receive(:till) # Mock the status waiter
      
      subject.wifi_on
      expect(subject).not_to have_received(:run_os_command)
    end

    it 'can turn wifi on when it is off', :disruptive do
      subject.wifi_off
      expect(subject.wifi_on?).to be(false)
      
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
    end
  end

  describe '#wifi_off' do
    it 'does nothing when wifi is already off' do
      allow(subject).to receive(:wifi_on?).and_return(false)
      allow(subject).to receive(:run_os_command)
      allow(subject).to receive(:till) # Mock the status waiter
      
      subject.wifi_off
      expect(subject).not_to have_received(:run_os_command)
    end

    it 'can turn wifi off when it is on', :disruptive do
      subject.wifi_on
      expect(subject.wifi_on?).to be(true)
      
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
      expect(subject.available_network_names).to be_nil_or_an_array_of_strings
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
      expect(subject.wifi_interface).to be_nil_or_a_string
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

  describe '#init_wifi_interface' do
    context 'when provided interface is valid' do
      it 'uses the provided wifi interface' do
        options = OpenStruct.new(wifi_interface: 'wlan1', verbose: false)
        model = subject.class.new(options)
        
        allow(model).to receive(:validate_os_preconditions)
        allow(model).to receive(:is_wifi_interface?).with('wlan1').and_return(true)
        
        model.init_wifi_interface
        expect(model.wifi_interface).to eq('wlan1')
      end
    end
    
    context 'when provided interface is invalid' do
      it 'raises InvalidInterfaceError' do
        options = OpenStruct.new(wifi_interface: 'invalid0', verbose: false)
        model = subject.class.new(options)
        
        allow(model).to receive(:validate_os_preconditions)
        allow(model).to receive(:is_wifi_interface?).with('invalid0').and_return(false)
        
        expect { model.init_wifi_interface }.to raise_error(WifiWand::InvalidInterfaceError)
      end
    end
  end

  describe '#nameservers_using_resolv_conf' do
    it 'returns nil when resolv.conf does not exist' do
      allow(File).to receive(:readlines).with('/etc/resolv.conf').and_raise(Errno::ENOENT)
      
      result = subject.nameservers_using_resolv_conf
      expect(result).to be_nil
    end
    
    it 'extracts nameservers from resolv.conf' do
      resolv_content = [
        "# This is a comment\n",
        "nameserver 8.8.8.8\n",
        "nameserver 1.1.1.1\n",
        "search example.com\n"
      ]
      
      allow(File).to receive(:readlines).with('/etc/resolv.conf').and_return(resolv_content)
      
      result = subject.nameservers_using_resolv_conf
      expect(result).to eq(['8.8.8.8', '1.1.1.1'])
    end
  end

  describe 'OS helpers' do
    it 'returns os_id and mac?/ubuntu? reflect os' do
      test_class = Class.new(WifiWand::BaseModel) do
        def self.os_id = :mac
        # implement required underscore methods to satisfy inherited verification
        def _available_network_names; []; end
        def _connected_network_name; nil; end
        def _connect(_n, _p); nil; end
        def _disconnect; nil; end
        def _ip_address; nil; end
        def _preferred_network_password(_n); nil; end
      end

      inst = test_class.allocate # skip initialize internals
      expect(inst.os).to eq(:mac)
      expect(inst.mac?).to be true
      expect(inst.ubuntu?).to be false
    end
  end

  describe '#public_ip_address_info error handling' do
    it 'raises PublicIPLookupError when response is not success' do
      # Ensure we call the real implementation, not the suite-wide stub
      allow(subject).to receive(:public_ip_address_info).and_call_original

      # Minimal Net::HTTP stubs
      response = instance_double('Net::HTTPResponse', code: '500', message: 'Internal Server Error')
      # Make the response not be a Net::HTTPSuccess for any class check
      allow(response).to receive(:is_a?).and_return(false)

      http = instance_double('Net::HTTP')
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:respond_to?).with(:write_timeout=).and_return(true)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect {
        subject.public_ip_address_info
      }.to raise_error(WifiWand::PublicIPLookupError, /HTTP error fetching public IP info: 500 Internal Server Error/)
    end
  end

  describe 'private helpers' do
    it 'memoizes private qr_code_generator helper' do
      first = subject.send(:qr_code_generator)
      second = subject.send(:qr_code_generator)
      expect(first).to be_a(WifiWand::Helpers::QrCodeGenerator)
      expect(second).to equal(first)
    end
  end

  describe 'subclass method validation' do
    it 'raises NotImplementedError for unimplemented required methods' do
      # Create an incomplete subclass for testing
      incomplete_class = Class.new(WifiWand::BaseModel) do
        def self.os_id
          :test
        end
        
        # Intentionally missing required underscore methods
      end
      
      expect {
        incomplete_class.verify_underscore_methods_implemented(incomplete_class)
      }.to raise_error(NotImplementedError, /must implement.*_available_network_names/)
    end

    # Note: TracePoint callback testing is unreliable due to test mocking interference.
    # Instead, we test verify_underscore_methods_implemented directly above.
    
    it 'calls NotImplementedError for dynamically defined required methods' do
      # Test the NotImplementedError by calling the method directly on BaseModel
      base_model_instance = WifiWand::BaseModel.allocate  # Don\'t call initialize
      
      expect {
        base_model_instance.default_interface
      }.to raise_error(NotImplementedError, /must implement default_interface/)
    end
  end

  describe '#wifi_info exception handling' do
    before do
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:wifi_interface).and_return('wlan0')
      allow(subject).to receive(:default_interface).and_return('wlan0')
      allow(subject).to receive(:connected_network_name).and_return('TestNet')
      allow(subject).to receive(:ip_address).and_return('192.168.1.100')
      allow(subject).to receive(:mac_address).and_return('aa:bb:cc:dd:ee:ff')
      allow(subject).to receive(:nameservers).and_return(['8.8.8.8'])
      
      # Remove the global mock for connected_to_internet? so we can test the real logic
      allow(subject).to receive(:connected_to_internet?).and_call_original
    end

    shared_context 'verbose test model setup' do
      let(:captured_output) { StringIO.new }
      
      let(:test_model) do
        model_options = OpenStruct.new(verbose: true, wifi_interface: nil, out_stream: captured_output)
        model = subject.class.new(model_options)
        
        # Mock the necessary methods for wifi_info to work
        allow(model).to receive(:validate_os_preconditions)
        allow(model).to receive(:detect_wifi_interface).and_return('wlan0')
        allow(model).to receive(:is_wifi_interface?).and_return(true)
        allow(model).to receive(:wifi_on?).and_return(true)
        allow(model).to receive(:wifi_interface).and_return('wlan0')
        allow(model).to receive(:default_interface).and_return('wlan0')
        allow(model).to receive(:connected_network_name).and_return('TestNet')
        allow(model).to receive(:ip_address).and_return('192.168.1.100')
        allow(model).to receive(:mac_address).and_return('aa:bb:cc:dd:ee:ff')
        allow(model).to receive(:nameservers).and_return(['8.8.8.8'])
        allow(model).to receive(:internet_tcp_connectivity?).and_return(true)
        allow(model).to receive(:dns_working?).and_return(true)
        allow(model).to receive(:sleep)  # Don\'t actually sleep
        
        model.init_wifi_interface
        model
      end
    end
    
    it 'handles internet_tcp_connectivity exceptions' do
      allow(subject).to receive(:internet_tcp_connectivity?).and_raise(StandardError, 'Network error')
      allow(subject).to receive(:dns_working?).and_return(true)
      allow(subject).to receive(:public_ip_address_info).and_return({'ip' => '1.2.3.4'})
      
      result = subject.wifi_info
      
      # Test the connectivity method directly
      direct_result = subject.connected_to_internet?(result['internet_tcp_connectivity'], result['dns_working'])
      
      expect(result['internet_tcp_connectivity']).to be false
      expect(result['internet_on']).to be false  # Should be false due to TCP failure
    end
    
    it 'handles dns_working exceptions' do
      allow(subject).to receive(:internet_tcp_connectivity?).and_return(true)
      allow(subject).to receive(:dns_working?).and_raise(StandardError, 'DNS error')
      allow(subject).to receive(:public_ip_address_info).and_return({'ip' => '1.2.3.4'})
      
      result = subject.wifi_info
      expect(result['dns_working']).to be false
      expect(result['internet_on']).to be false  # Should be false due to DNS failure
    end

    context 'public IP address handling' do
      before do
        allow(subject).to receive(:internet_tcp_connectivity?).and_return(true)
        allow(subject).to receive(:dns_working?).and_return(true)
      end
      
      it 'retries on network timeout and succeeds' do
        allow(subject).to receive(:public_ip_address_info)
          .and_raise(Errno::ETIMEDOUT)
          .once
        allow(subject).to receive(:public_ip_address_info)
          .and_return({'ip' => '1.2.3.4'})
          .once
        allow(subject).to receive(:sleep)
        
        result = subject.wifi_info
        expect(result['public_ip']).to eq({'ip' => '1.2.3.4'})
      end
      
      # These tests are complex because they test error handling paths within wifi_info
      # that involve verbose logging. We simplify by testing the behavior more directly.
      
      context 'with verbose logging enabled' do
        include_context 'verbose test model setup'
        
        it 'handles retry failure with verbose logging' do
          # Make public_ip_address_info fail twice (triggering retry path)
          allow(test_model).to receive(:public_ip_address_info)
            .and_raise(Errno::ETIMEDOUT)
            .twice
          
          result = test_model.wifi_info
          expect(result['public_ip']).to be_nil
          expect(captured_output.string).to match(/Warning: Could not obtain public IP info/)
        end
        
        it 'handles JSON parsing errors' do
          # Make public_ip_address_info fail with JSON parse error
          allow(test_model).to receive(:public_ip_address_info)
            .and_raise(JSON::ParserError, 'Invalid JSON')
          
          result = test_model.wifi_info
          expect(result['public_ip']).to be_nil
          expect(captured_output.string).to match(/Warning: Public IP service returned invalid data/)
        end
        
        it 'handles other exceptions' do
          # Make public_ip_address_info fail with runtime error
          allow(test_model).to receive(:public_ip_address_info)
            .and_raise(RuntimeError, 'Unknown error')
          
          result = test_model.wifi_info
          expect(result['public_ip']).to be_nil
          expect(captured_output.string).to match(/Warning: Public IP lookup failed: RuntimeError/)
        end
      end
    end
  end

  describe '#connected_to?' do
    it 'returns true when connected to specified network' do
      allow(subject).to receive(:connected_network_name).and_return('TestNetwork')
      
      expect(subject.connected_to?('TestNetwork')).to be true
    end
    
    it 'returns false when connected to different network' do
      allow(subject).to receive(:connected_network_name).and_return('OtherNetwork')
      
      expect(subject.connected_to?('TestNetwork')).to be false
    end
    
    it 'returns false when not connected to any network' do
      allow(subject).to receive(:connected_network_name).and_return(nil)
      
      expect(subject.connected_to?('TestNetwork')).to be false
    end
  end

  describe '#remove_preferred_networks' do
    before do
      allow(subject).to receive(:preferred_networks).and_return(['Network1', 'Network2', 'Network3'])
      allow(subject).to receive(:remove_preferred_network)
    end
    
    it 'handles array as first argument' do
      networks_to_remove = ['Network1', 'Network2']
      subject.remove_preferred_networks(networks_to_remove)
      
      expect(subject).to have_received(:remove_preferred_network).with('Network1')
      expect(subject).to have_received(:remove_preferred_network).with('Network2')
    end
    
    it 'handles multiple string arguments' do
      subject.remove_preferred_networks('Network1', 'Network2')
      
      expect(subject).to have_received(:remove_preferred_network).with('Network1')
      expect(subject).to have_received(:remove_preferred_network).with('Network2')
    end
    
    it 'ignores non-existent networks' do
      subject.remove_preferred_networks('Network1', 'NonExistent')
      
      expect(subject).to have_received(:remove_preferred_network).with('Network1')
      expect(subject).not_to have_received(:remove_preferred_network).with('NonExistent')
    end
  end

  describe '#try_os_command_until' do
    it 'delegates to command executor' do
      command = 'test command'
      stop_condition = ->(output) { output.include?('success') }
      max_tries = 50
      
      allow(subject.command_executor).to receive(:try_os_command_until)
        .with(command, stop_condition, max_tries)
        .and_return('success output')
      
      result = subject.try_os_command_until(command, stop_condition, max_tries)
      expect(result).to eq('success output')
    end
  end

  describe '#random_mac_address' do
    it 'generates a valid MAC address format' do
      mac = subject.random_mac_address
      expect(mac).to match(/\A[0-9a-f]{2}(:[0-9a-f]{2}){5}\z/)
    end

    it 'generates different addresses on successive calls' do
      mac1 = subject.random_mac_address
      mac2 = subject.random_mac_address

      # Very unlikely to be the same (1 in 2^48 chance)
      expect(mac1).not_to eq(mac2)
    end

    it 'generates locally administered unicast MAC addresses' do
      # Generate multiple addresses to ensure consistency
      10.times do
        mac = subject.random_mac_address
        first_byte = mac[0..1].to_i(16)

        # Check that multicast bit (bit 0) is cleared (0)
        multicast_bit = first_byte & 0x01
        expect(multicast_bit).to eq(0), "MAC #{mac} has multicast bit set"

        # Check that locally administered bit (bit 1) is set (1)
        locally_administered_bit = (first_byte & 0x02) >> 1
        expect(locally_administered_bit).to eq(1), "MAC #{mac} does not have locally administered bit set"

        # Verify the pattern: first byte should be xxxxxx10 where x can be 0 or 1
        # This means the first byte should match the pattern where bits 0-1 are 10
        expected_pattern = first_byte & 0x03
        expect(expected_pattern).to eq(2), "MAC #{mac} first byte #{first_byte.to_s(16)} does not match locally administered unicast pattern"
      end
    end
  end

  describe '#status_line_data' do
    it 'returns a hash with the correct keys' do
      allow(subject).to receive(:fast_connectivity?).and_return(true)

      data = subject.status_line_data
      expect(data).to be_a(Hash)

      # All models should have wifi_on and internet_connected
      expect(data.keys).to include(:wifi_on, :internet_connected)

      # network_name is only included if show_network_name_in_status? is true
      expect(data.has_key?(:network_name)).to eq(subject.show_network_name_in_status?)

    end

    test_cases = {
      'when everything is working' => {
        wifi_on: true,
        network_name: 'TestNetwork',
        internet_connected: true
      },
      'when wifi is off' => {
        wifi_on: false,
        network_name: nil,
        internet_connected: false
      }
    }

    test_cases.each do |context, expected_data|
      it "returns correct data #{context}" do
        allow(subject).to receive(:wifi_on?).and_return(expected_data[:wifi_on])
        allow(subject).to receive(:connected_network_name).and_return(expected_data[:network_name])
        allow(subject).to receive(:fast_connectivity?).and_return(expected_data[:internet_connected])

        data = subject.status_line_data

        # All models should return wifi_on and internet_connected
        expect(data[:wifi_on]).to eq(expected_data[:wifi_on])
        expect(data[:internet_connected]).to eq(expected_data[:internet_connected])

        # network_name is only included if show_network_name_in_status? is true
        if subject.show_network_name_in_status?
          expect(data[:network_name]).to eq(expected_data[:network_name])
        else
          expect(data).not_to have_key(:network_name)
        end
      end
    end

    it 'returns nil when an exception is raised' do
      allow(subject).to receive(:wifi_on?).and_raise(StandardError)
      data = subject.status_line_data
      expect(data).to be_nil
    end
  end

  describe 'private methods' do
    describe '#connected_network_password' do
      it 'returns nil when not connected to any network' do
        allow(subject).to receive(:connected_network_name).and_return(nil)
        
        result = subject.send(:connected_network_password)
        expect(result).to be_nil
      end
      
      it 'returns password for connected network' do
        network_name = 'TestNetwork'
        expected_password = 'test_password'
        
        allow(subject).to receive(:connected_network_name).and_return(network_name)
        allow(subject).to receive(:preferred_network_password)
          .with(network_name)
          .and_return(expected_password)
        
        result = subject.send(:connected_network_password)
        expect(result).to eq(expected_password)
      end
    end
  end

  describe '#generate_qr_code' do
    let(:network_name) { 'TestNetwork' }
    let(:network_password) { 'test_password' }
    let(:security_type) { 'WPA2' }
    let(:expected_filename) { 'TestNetwork-qr-code.png' }

    before(:each) do
      allow(subject).to receive(:command_available?).with('qrencode').and_return(true)
      allow(subject).to receive(:connected_network_name).and_return(network_name)
      allow(subject).to receive(:connected_network_password).and_return(network_password)
      allow(subject).to receive(:connection_security_type).and_return(security_type)
      allow(subject).to receive(:network_hidden?).and_return(false)
      allow(subject).to receive(:run_os_command).and_return(command_result(stdout: ''))

      # Mock all methods that could make real system calls
      allow(subject).to receive(:preferred_networks).and_return([network_name])
      allow(subject).to receive(:preferred_network_password).and_return(network_password)
      allow(subject).to receive(:_preferred_network_password).and_return(network_password)
    end

    context 'dependency checking' do
      [
        [:ubuntu, 'sudo apt install qrencode'],
        [:mac, 'brew install qrencode']
      ].each do |os_id, expected_command|
        it "raises error with correct install command for #{os_id}" do
          allow(subject).to receive(:command_available?).with('qrencode').and_return(false)
          allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: os_id))
          
        expect { silence_output { subject.generate_qr_code } }.to raise_error(WifiWand::Error, /#{Regexp.escape(expected_command)}/)
        end
      end

      it 'raises error with generic message for unknown OS' do
        allow(subject).to receive(:command_available?).with('qrencode').and_return(false)
        allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: :unknown))
        
        expect { silence_output { subject.generate_qr_code } }.to raise_error(WifiWand::Error, /install qrencode using your system package manager/)
      end
    end

    context 'network connection validation' do
      it 'raises error when not connected to any network' do
        allow(subject).to receive(:connected_network_name).and_return(nil)
        
        expect { silence_output { subject.generate_qr_code } }.to raise_error(WifiWand::Error, /Not connected to any WiFi network/)
      end
    end

    context 'QR code generation with different security types' do
      [
        ['WPA',  'WPA'],
        ['WPA2', 'WPA'], 
        ['WPA3', 'WPA'],
        ['WEP',  'WEP'],
        [nil,    'WPA']
      ].each do |input_security, expected_qr_security|
        it "generates correct QR string for #{input_security || 'open network'}" do
          allow(subject).to receive(:connection_security_type).and_return(input_security)
          expected_qr_string = "WIFI:T:#{expected_qr_security};S:TestNetwork;P:test_password;H:false;;"

          silence_output { subject.generate_qr_code }

          expect(subject).to have_received(:run_os_command)
            .with(%w[qrencode -o TestNetwork-qr-code.png] + [expected_qr_string])
        end
      end

      it 'defaults to WPA when security type is unknown but password exists' do
        allow(subject).to receive(:connection_security_type).and_return('RSN')
        expected_qr_string = 'WIFI:T:WPA;S:TestNetwork;P:test_password;H:false;;'

        silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_os_command)
          .with(%w[qrencode -o TestNetwork-qr-code.png] + [expected_qr_string])
      end
    end

    context 'special character escaping' do
      [
        ['Network;With;Semicolons', 'password,with,commas', 'WIFI:T:WPA;S:Network\;With\;Semicolons;P:password\,with\,commas;H:false;;'],
        ['Network:With:Colons', 'password:with:colons', 'WIFI:T:WPA;S:Network\:With\:Colons;P:password\:with\:colons;H:false;;'],
        ['Network\With\Backslashes', 'pass\word', 'WIFI:T:WPA;S:Network\\\\With\\\\Backslashes;P:pass\\\\word;H:false;;'],
        ['Regular-Network_Name', 'regularPassword123', 'WIFI:T:WPA;S:Regular-Network_Name;P:regularPassword123;H:false;;']
      ].each do |test_network, test_password, expected_qr_string|
        it "properly escapes special characters in '#{test_network}' / '#{test_password}'" do
          allow(subject).to receive(:connected_network_name).and_return(test_network)
          allow(subject).to receive(:connected_network_password).and_return(test_password)

          silence_output { subject.generate_qr_code }

          safe_network_name = test_network.gsub(/[^\w\-_]/, '_')
          expected_filename = "#{safe_network_name}-qr-code.png"

          expect(subject).to have_received(:run_os_command)
            .with(['qrencode', '-o', expected_filename, expected_qr_string])
        end
      end
    end

    context 'filename generation' do
      [
        ['SimpleNetwork',       'SimpleNetwork-qr-code.png'],
        ['Network With Spaces', 'Network_With_Spaces-qr-code.png'],
        ['Network@#$%^&*()!',   'Network__________-qr-code.png'],
        ['cafe-reseau',         'cafe-reseau-qr-code.png']
      ].each do |input_name, expected_filename|
        it "generates safe filename for '#{input_name}'" do
          allow(subject).to receive(:connected_network_name).and_return(input_name)
          
          result = silence_output { subject.generate_qr_code }
          
          expect(result).to eq(expected_filename)
        end
      end
    end

    context 'open network handling' do
      it 'generates QR code for open network (no password)' do
        allow(subject).to receive(:connected_network_password).and_return(nil)
        allow(subject).to receive(:connection_security_type).and_return(nil)
        expected_qr_string = 'WIFI:T:nopass;S:TestNetwork;P:;H:false;;'

        result = silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_os_command)
          .with(%w[qrencode -o TestNetwork-qr-code.png] + [expected_qr_string])
        expect(result).to eq('TestNetwork-qr-code.png')
      end
    end

    context 'error handling' do
      it 'raises WifiWand::Error when qrencode command fails' do
        allow(subject).to receive(:run_os_command)
          .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'qrencode', 'Command failed'))
        
        expect { silence_output { subject.generate_qr_code } }.to raise_error(WifiWand::Error, /Failed to generate QR code/)
      end
    end
  end
end
