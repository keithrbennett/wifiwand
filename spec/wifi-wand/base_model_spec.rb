# frozen_string_literal: true

require_relative '../../lib/wifi-wand/operating_systems'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

describe 'Common WiFi Model Behavior (All OS)' do
  # Mock OS calls to prevent real system interaction during ordinary tests
  # Automatically instantiate the correct model for the current OS
  subject { create_test_model }

  before do
    # Mock interface discovery for both OS types
    allow_any_instance_of(WifiWand::UbuntuModel).to receive(:probe_wifi_interface).and_return('wlp0s20f3')
    if defined?(WifiWand::MacOsModel)
      allow_any_instance_of(WifiWand::MacOsModel).to receive(:probe_wifi_interface).and_return('en0')
    end

    # Mock all OS-calling methods to prevent real system calls in ordinary tests
    # Only skip these mocks for examples that intentionally use the real environment.
    # Use RSpec.current_example to get the current running example
    unless uses_real_env?
      # Also mock the underlying NetworkConnectivityTester to prevent real network calls
      tester = WifiWand::NetworkConnectivityTester
      allow_any_instance_of(tester).to receive(:tcp_connectivity?).and_return(true)
      allow_any_instance_of(tester).to receive(:dns_working?).and_return(true)
      allow_any_instance_of(tester).to receive(:captive_portal_state).and_return(:free)
      allow(subject.connection_manager).to receive(:wait_for_connection_activation)

      # Mock low-level OS command execution to prevent real system calls
      # but allow higher-level methods to be called for testing
      allow(subject).to receive_messages(
        wifi_on?:                   true,
        available_network_names:    %w[TestNetwork1 TestNetwork2],
        connected_network_name:     'TestNetwork1',
        ip_address:                 '192.168.1.100',
        mac_address:                'aa:bb:cc:dd:ee:ff',
        default_interface:          'wlan0',
        nameservers:                ['8.8.8.8', '8.8.4.4'],
        preferred_networks:         %w[TestNetwork1 SavedNetwork1],
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :free,
        fast_connectivity?:         true,
        run_os_command:             command_result(stdout: ''),
        till:                       nil
      )
    end
  end


  # These tests run on any OS - interface consistency tests
  # Check current wifi state and create appropriate contexts
  let(:current_wifi_on) { subject.wifi_on? }

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
        'wifi_on', 'internet_tcp_connectivity', 'dns_working', 'captive_portal_state',
        'internet_connectivity_state', 'interface', 'default_interface', 'network', 'ip_address',
        'mac_address', 'nameservers', 'preferred_networks', 'available_networks', 'timestamp'
      )

      expect([true, false]).to include(result['wifi_on'])
      expect([true, false]).to include(result['internet_tcp_connectivity'])
      expect([true, false]).to include(result['dns_working'])
      expect(%i[free present indeterminate]).to include(result['captive_portal_state'])
      expect(%i[reachable unreachable indeterminate]).to include(result['internet_connectivity_state'])
      expect(result['preferred_networks']).to all(be_a(String))
      expect(result['available_networks']).to all(be_a(String))
      expect(result['timestamp']).to be_a(Time)
    end

    it 'returns empty arrays for network lists when those lookups fail' do
      allow(subject).to receive(:preferred_networks).and_raise(WifiWand::Error, 'saved networks unavailable')
      allow(subject).to receive(:available_network_names).and_raise(WifiWand::Error, 'scan unavailable')

      result = subject.wifi_info

      expect(result['preferred_networks']).to eq([])
      expect(result['available_networks']).to eq([])
    end

    it 'returns nil when default_interface lookup fails' do
      allow(subject).to receive(:default_interface).and_raise(WifiWand::Error, 'default route unavailable')

      result = subject.wifi_info

      expect(result).to be_a(Hash)
      expect(result['default_interface']).to be_nil
    end

    it 'returns nil when mac_address lookup fails' do
      allow(subject).to receive(:mac_address).and_raise(WifiWand::Error, 'mac lookup unavailable')

      result = subject.wifi_info

      expect(result).to be_a(Hash)
      expect(result['mac_address']).to be_nil
    end

    it 'returns empty array when nameservers lookup fails' do
      allow(subject).to receive(:nameservers).and_raise(WifiWand::Error, 'dns config unavailable')

      result = subject.wifi_info

      expect(result).to be_a(Hash)
      expect(result['nameservers']).to eq([])
    end

    it 'does not include public IP data' do
      result = subject.wifi_info
      expect(result).not_to have_key('public_ip')
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
      mock_connection_manager = double('ConnectionManager', last_connection_used_saved_password?: true)
      subject.connection_manager = mock_connection_manager

      expect(mock_connection_manager).to receive(:connect)
        .with(network_name, nil, skip_saved_password_lookup: false)

      subject.connect(network_name)
      expect(subject.last_connection_used_saved_password?).to be true
    end

    it 'does not use saved password when one is provided' do
      network_name = 'SavedNetwork1'
      provided_password = 'provided_password'
      mock_connection_manager = double('ConnectionManager', last_connection_used_saved_password?: false)
      subject.connection_manager = mock_connection_manager

      expect(mock_connection_manager).to receive(:connect)
        .with(network_name, provided_password, skip_saved_password_lookup: false)

      subject.connect(network_name, provided_password)
      expect(subject.last_connection_used_saved_password?).to be false
    end

    it 'does not use saved password when network is not preferred' do
      network_name = 'UnknownNetwork'
      mock_connection_manager = double('ConnectionManager', last_connection_used_saved_password?: false)
      subject.connection_manager = mock_connection_manager

      expect(mock_connection_manager).to receive(:connect)
        .with(network_name, nil, skip_saved_password_lookup: false)

      subject.connect(network_name)
      expect(subject.last_connection_used_saved_password?).to be false
    end
  end

  describe '#disconnect' do
    subject(:model) { test_model_class.new }

    let(:test_model_class) do
      Class.new(WifiWand::BaseModel) do
        def self.os_id = :mac
        def _available_network_names = []
        def _connected_network_name = nil
        def _connect(_network_name, _password = nil) = nil
        def _disconnect = nil
        def _ip_address = nil
        def _preferred_network_password(_network_name) = nil
      end
    end

    it 'raises a dedicated error when the interface remains associated' do
      allow(model).to receive_messages(
        wifi_on?:               true,
        associated?:            true,
        connected_network_name: 'TestNet'
      )
      allow(model).to receive(:_disconnect)
      allow(model).to receive(:till)
        .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
        .and_raise(WifiWand::WaitTimeoutError.new(:disassociated, 5))

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'raises when disassociation is not stable after the initial wait succeeds' do
      allow(model).to receive_messages(
        wifi_on?:                            true,
        connected_network_name:              'TestNet',
        disconnect_stability_window_in_secs: 0.1
      )
      allow(model).to receive(:associated?).and_return(true, false, true)
      allow(model).to receive(:_disconnect)
      allow(model).to receive(:till)
        .with(:disassociated, timeout_in_secs: WifiWand::TimingConstants::STATUS_WAIT_TIMEOUT_SHORT)
        .and_return(nil)
      allow(model).to receive(:sleep)

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'is a no-op when wifi is already disassociated' do
      allow(model).to receive_messages(wifi_on?: true, associated?: false)
      allow(model).to receive(:_disconnect)
      allow(model).to receive(:till)

      expect(model.disconnect).to be_nil
      expect(model).not_to have_received(:_disconnect)
      expect(model).not_to have_received(:till)
    end
  end

  describe '#disconnect', :real_env_read_write do
    it 'either disassociates or surfaces a verified disconnect failure', :needs_sudo_access do
      subject.wifi_on

      begin
        subject.disconnect
        expect(subject.associated?).to be(false)
        expect { subject.disconnect }.not_to raise_error
      rescue WifiWand::NetworkDisconnectionError => e
        expect(subject.mac?).to be(true)
        expect(subject.associated?).to be(true)
        expect(e.reason).to match(/still associated with|interface remained associated/)
      end
    end
  end

  describe '#associated?', :real_env_read_only do
    it 'returns a boolean' do
      expect([true, false]).to include(subject.associated?)
    end

    it 'is true when wifi is on and a non-empty network name is present' do
      skip 'WiFi is currently off' unless subject.wifi_on?

      name = subject.connected_network_name
      skip 'No visible network name is currently available' if name.nil? || name.empty?

      expect(subject.associated?).to be(true)
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

    it 'can turn wifi on when it is off', :real_env_read_write do
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

    it 'can turn wifi off when it is on', :real_env_read_write do
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

  describe '#available_network_names', :real_env_read_write do
    it 'can list available networks' do
      subject.wifi_on
      expect(subject.available_network_names).to be_an(Array).and all(be_a(String))
    end
  end

  describe '#till', :real_env_read_write do
    # These tests exercise the real OS predicates (wifi_on?, associated?,
    # internet_connectivity_state wired through StatusWaiter against live hardware,
    # as smoke tests for host-integrated behavior. Polling/state-transition
    # semantics are covered in deterministic mocked specs below.

    context 'when target is a wifi power state (:wifi_on / :wifi_off)' do
      it 'returns nil immediately when WiFi is already on' do
        subject.wifi_on
        expect(subject.till(:wifi_on)).to be_nil
      end

      it 'returns nil immediately when WiFi is already off' do
        subject.wifi_off
        expect(subject.till(:wifi_off)).to be_nil
      end

      it 'raises WaitTimeoutError for :wifi_on when WiFi stays off and timeout expires' do
        subject.wifi_off
        expect do
          subject.till(:wifi_on, timeout_in_secs: 1)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end

      it 'raises WaitTimeoutError for :wifi_off when WiFi stays on and timeout expires' do
        subject.wifi_on
        expect do
          subject.till(:wifi_off, timeout_in_secs: 1)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end
    end

    context 'when target is an internet reachability state (:internet_on / :internet_off)' do
      before { subject.wifi_on }

      def require_reachable_internet!(model, description)
        state = model.internet_connectivity_state
        return if state == :reachable

        skip "Skipping #{description}: Internet connectivity state is #{state.inspect}, not :reachable."
      end

      it 'returns nil immediately for :internet_on when Internet is reachable' do
        require_reachable_internet!(subject, ':internet_on real-environment check')
        expect(subject.till(:internet_on)).to be_nil
      end

      it 'raises WaitTimeoutError for :internet_off when Internet is reachable and timeout expires' do
        require_reachable_internet!(subject, ':internet_off timeout real-environment check')
        expect do
          subject.till(:internet_off, timeout_in_secs: 1, wait_interval_in_secs: 0.1)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end
    end
  end

  describe '#till' do
    context 'with removed legacy state names' do
      before do
        allow(subject).to receive(:till).and_call_original
      end

      it 'raises ArgumentError with migration hint for :conn' do
        expect { subject.till(:conn) }.to raise_error(ArgumentError, /:conn.*was removed/i)
      end

      it 'raises ArgumentError with migration hint for :disc' do
        expect { subject.till(:disc) }.to raise_error(ArgumentError, /:disc.*was removed/i)
      end

      it 'raises ArgumentError with migration hint for :on' do
        expect { subject.till(:on) }.to raise_error(ArgumentError, /:on.*was removed/i)
      end

      it 'raises ArgumentError with migration hint for :off' do
        expect { subject.till(:off) }.to raise_error(ArgumentError, /:off.*was removed/i)
      end
    end

    context 'when target is an association state (:associated / :disassociated)' do
      before do
        allow(subject).to receive(:till).and_call_original
        allow_any_instance_of(WifiWand::StatusWaiter).to receive(:sleep)
      end

      it 'returns nil immediately for :associated when already associated' do
        allow(subject).to receive(:associated?).and_return(true)

        expect(subject.till(:associated)).to be_nil
      end

      it 'returns nil immediately for :disassociated when already disassociated' do
        allow(subject).to receive(:associated?).and_return(false)

        expect(subject.till(:disassociated)).to be_nil
      end

      it 'waits for :associated until association is observed' do
        allow(subject).to receive(:associated?).and_return(false, false, true)

        expect(
          subject.till(:associated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        ).to be_nil
      end

      it 'waits for :disassociated until association clears' do
        allow(subject).to receive(:associated?).and_return(true, true, false)

        expect(
          subject.till(:disassociated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        ).to be_nil
      end

      it 'raises WaitTimeoutError for :associated when association never appears' do
        allow(subject).to receive(:associated?).and_return(false)
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1000.0, 1001.1)

        expect do
          subject.till(:associated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end

      it 'raises WaitTimeoutError for :disassociated when association never clears' do
        allow(subject).to receive(:associated?).and_return(true)
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1000.0, 1001.1)

        expect do
          subject.till(:disassociated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end
    end
  end


  # The following tests run commands and verify they complete without error,
  # testing both wifi on and wifi off states
  shared_examples 'interface commands complete without error' do
    it 'can determine if connected to Internet' do
      expect { subject.internet_connectivity_state }.not_to raise_error
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
  end

  def verify_interface_commands_complete_without_error
    aggregate_failures 'interface commands' do
      expect { subject.internet_connectivity_state }.not_to raise_error
      expect(subject.wifi_interface).to be_nil_or_a_string
      expect(subject.wifi_info).to be_a(Hash)

      preferred_networks = subject.preferred_networks
      expect(preferred_networks).to be_a(Array)
      expect(preferred_networks).to all(be_a(String))

      expect([true, false]).to include(subject.wifi_on?)
    end
  end


  # Ordinary context - only runs when wifi is already on
  context 'when wifi starts on' do
    before do
      skip 'Wifi is not currently on' unless current_wifi_on
    end

    it_behaves_like 'interface commands complete without error', true
  end

  # Ordinary context - only runs when wifi starts off
  context 'when wifi starts off' do
    before do
      skip 'Wifi is currently on' if current_wifi_on
    end

    it_behaves_like 'interface commands complete without error', false
  end

  # Real-environment read-write contexts
  context 'when wifi starts on (real environment)', :real_env_read_write do
    before { subject.wifi_on }

    it_behaves_like 'interface commands complete without error'

    it 'can query connected network name' do
      expect(subject.connected_network_name).to be_a(String).or be_nil
    end
  end

  context 'when wifi starts off (real environment)', :real_env_read_write do
    before { subject.wifi_off }

    it_behaves_like 'interface commands complete without error'

    it 'raises WifiOffError when querying connected network name' do
      expect { subject.connected_network_name }.to raise_error(WifiWand::WifiOffError)
    end
  end

  describe '#restore_network_state' do
    let(:valid_state) do
      {
        wifi_enabled:     true,
        network_name:     'TestNetwork',
        network_password: 'testpass',
        interface:        'wlan0',
      }
    end

    it 'returns :no_state_to_restore when state is nil' do
      expect(subject.restore_network_state(nil)).to eq(:no_state_to_restore)
    end

    it 'returns :already_connected when already on correct network' do
      allow(subject).to receive_messages(
        connection_ready?:      true,
        wifi_on?:               true,
        connected?:             true,
        connected_network_name: 'TestNetwork'
      )

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
        "search example.com\n",
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
        def _available_network_names = []
        def _connected_network_name = nil
        def _connect(_n, _p) = nil
        def _disconnect = nil
        def _ip_address = nil
        def _preferred_network_password(_n) = nil
      end

      inst = test_class.allocate # skip initialize internals
      expect(inst.os).to eq(:mac)
      expect(inst.mac?).to be true
      expect(inst.ubuntu?).to be false
    end
  end

  describe '#public_ip_address error handling' do
    it 'raises PublicIPLookupError when response is not success' do
      allow(subject).to receive(:public_ip_address).and_call_original

      response = instance_double(Net::HTTPResponse, code: '500', message: 'Internal Server Error')
      allow(response).to receive(:is_a?).and_return(false)

      http = instance_double(Net::HTTP)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:respond_to?).with(:write_timeout=).and_return(true)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect do
        subject.public_ip_address
      end.to raise_error(WifiWand::PublicIPLookupError,
        'Public IP lookup failed: HTTP 500 Internal Server Error')
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

      expect do
        incomplete_class.verify_required_methods_implemented(incomplete_class)
      end.to raise_error(NotImplementedError, /must implement.*_available_network_names/)
    end

    it 'raises NotImplementedError when a subclass does not override required public methods' do
      incomplete_class = Class.new(WifiWand::BaseModel) do
        def self.os_id
          :test
        end

        def _available_network_names = []
        def _connected_network_name = nil
        def _connect(_network_name, _password = nil) = nil
        def _disconnect = nil
        def _ip_address = nil
        def _preferred_network_password(_network_name) = nil
      end

      expect do
        incomplete_class.verify_required_methods_implemented(incomplete_class)
      end.to raise_error(NotImplementedError, /must implement.*open_resource/)
    end

    # NOTE: TracePoint callback testing is unreliable due to test mocking interference.
    # Instead, we test verify_required_methods_implemented directly above.

    it 'calls NotImplementedError for dynamically defined required methods' do
      # Test the NotImplementedError by calling the method directly on BaseModel
      base_model_instance = WifiWand::BaseModel.allocate  # Don\'t call initialize

      expect do
        base_model_instance.default_interface
      end.to raise_error(NotImplementedError, /must implement default_interface/)
    end
  end

  describe '#wifi_info exception handling' do
    before do
      allow(subject).to receive_messages(
        wifi_on?:               true,
        wifi_interface:         'wlan0',
        default_interface:      'wlan0',
        connected_network_name: 'TestNet',
        ip_address:             '192.168.1.100',
        mac_address:            'aa:bb:cc:dd:ee:ff',
        nameservers:            ['8.8.8.8']
      )

      allow(subject).to receive(:internet_connectivity_state).and_call_original
    end

    shared_context 'for verbose test model setup' do
      let(:captured_output) { StringIO.new }

      let(:test_model) do
        model_options = OpenStruct.new(verbose: true, wifi_interface: nil, out_stream: captured_output)
        model = subject.class.new(model_options)

        # Mock the necessary methods for wifi_info to work
        allow(model).to receive(:validate_os_preconditions)
        allow(model).to receive_messages(
          probe_wifi_interface:       'wlan0',
          is_wifi_interface?:         true,
          wifi_on?:                   true,
          wifi_interface:             'wlan0',
          default_interface:          'wlan0',
          connected_network_name:     'TestNet',
          ip_address:                 '192.168.1.100',
          mac_address:                'aa:bb:cc:dd:ee:ff',
          nameservers:                ['8.8.8.8'],
          internet_tcp_connectivity?: true,
          dns_working?:               true
        )
        allow(model).to receive(:sleep)  # Don\'t actually sleep

        model.init_wifi_interface
        model
      end
    end

    it 'handles internet_tcp_connectivity exceptions' do
      allow(subject).to receive(:internet_tcp_connectivity?).and_raise(SocketError, 'Network error')
      allow(subject).to receive_messages(dns_working?: true)

      result = subject.wifi_info

      subject.internet_connectivity_state(
        result['internet_tcp_connectivity'],
        result['dns_working'],
        result['captive_portal_state']
      )

      expect(result['internet_tcp_connectivity']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
    end

    it 'handles dns_working exceptions' do
      allow(subject).to receive(:dns_working?).and_raise(SocketError, 'DNS error')
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: true
      )

      result = subject.wifi_info
      expect(result['dns_working']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
    end

    it 'does not call captive_portal_state when TCP fails' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               true
      )
      expect(subject).not_to receive(:captive_portal_state)

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'does not call captive_portal_state when DNS fails' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               false
      )
      expect(subject).not_to receive(:captive_portal_state)

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'does not call captive_portal_state when both TCP and DNS fail' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               false
      )
      expect(subject).not_to receive(:captive_portal_state)

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'calls captive_portal_state when both TCP and DNS succeed' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        captive_portal_state:       :free
      )
      expect(subject).to receive(:captive_portal_state).and_return(:free)

      subject.wifi_info
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
      allow(subject).to receive(:preferred_networks).and_return(%w[Network1 Network2 Network3])
      allow(subject).to receive(:remove_preferred_network)
    end

    it 'handles array as first argument' do
      networks_to_remove = %w[Network1 Network2]
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

    it 'uses has_preferred_network? instead of exact preferred_network string matches' do
      allow(subject).to receive(:has_preferred_network?).with('Network1').and_return(true)
      allow(subject).to receive(:has_preferred_network?).with('AliasForNetwork2').and_return(true)
      allow(subject).to receive(:has_preferred_network?).with('NonExistent').and_return(false)

      subject.remove_preferred_networks('Network1', 'AliasForNetwork2', 'NonExistent')

      expect(subject).to have_received(:remove_preferred_network).with('Network1')
      expect(subject).to have_received(:remove_preferred_network).with('AliasForNetwork2')
      expect(subject).not_to have_received(:remove_preferred_network).with('NonExistent')
    end

    it 'returns the actual deleted profile names reported by the model' do
      allow(subject).to receive(:has_preferred_network?).with('Network1').and_return(true)
      allow(subject).to receive(:has_preferred_network?).with('NonExistent').and_return(false)
      allow(subject).to receive(:remove_preferred_network).with('Network1')
        .and_return(['Network1', 'Network1 1'])

      expect(subject.remove_preferred_networks('Network1', 'NonExistent')).to eq(['Network1', 'Network1 1'])
    end

    it 'falls back to the requested network name when a model returns nil' do
      allow(subject).to receive(:has_preferred_network?).with('Network1').and_return(true)
      allow(subject).to receive(:remove_preferred_network).with('Network1').and_return(nil)

      expect(subject.remove_preferred_networks('Network1')).to eq(['Network1'])
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
        expect(expected_pattern).to eq(2),
          "MAC #{mac} first byte #{first_byte.to_s(16)} does not match locally administered unicast pattern"
      end
    end
  end

  describe '#status_line_data' do
    let(:builder) { instance_double(WifiWand::StatusLineDataBuilder) }
    let(:progress_callback) { ->(_data) {} }

    it 'delegates to StatusLineDataBuilder with the current model context' do
      expect(WifiWand::StatusLineDataBuilder).to receive(:new).with(
        subject,
        verbose:                 subject.verbose_mode,
        output:                  subject.out_stream,
        expected_network_errors: WifiWand::BaseModel::EXPECTED_NETWORK_ERRORS
      ).and_return(builder)
      expect(builder).to receive(:call).with(progress_callback: progress_callback).and_return({})

      subject.status_line_data(progress_callback: progress_callback)
    end

    it 'returns the builder result unchanged' do
      allow(WifiWand::StatusLineDataBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:call).and_return({ wifi_on: true })

      expect(subject.status_line_data).to eq(wifi_on: true)
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
    let(:delete_qr_code_files) { -> { FileUtils.rm_f(Dir.glob('*-qr-code.png')) } }

    before do
      delete_qr_code_files.call
      allow(subject).to receive(:command_available?).with('qrencode').and_return(true)

      # Mock all methods that could make real system calls
      allow(subject).to receive_messages(
        connected_network_name:      network_name,
        connected_network_password:  network_password,
        connection_security_type:    security_type,
        network_hidden?:             false,
        run_os_command:              command_result(stdout: ''),
        preferred_networks:          [network_name],
        preferred_network_password:  network_password,
        _preferred_network_password: network_password
      )
    end

    after do
      delete_qr_code_files.call
    end

    context 'when checking dependencies' do
      [
        [:ubuntu, 'sudo apt install qrencode'],
        [:mac, 'brew install qrencode'],
      ].each do |os_id, expected_command|
        it "raises error with correct install command for #{os_id}" do
          allow(subject).to receive(:command_available?).with('qrencode').and_return(false)
          allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: os_id))

          expect do
            silence_output do
              subject.generate_qr_code
            end
          end.to raise_error(WifiWand::Error, /#{Regexp.escape(expected_command)}/)
        end
      end

      it 'raises error with generic message for unknown OS' do
        allow(subject).to receive(:command_available?).with('qrencode').and_return(false)
        allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: :unknown))

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error,
            /install qrencode using your system package manager/)
      end
    end

    context 'when validating network connection' do
      it 'raises error when not connected to any network' do
        allow(subject).to receive(:connected_network_name).and_return(nil)

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error, /Not connected to any WiFi network/)
      end
    end

    context 'when generating QR codes with different security types' do
      [
        %w[WPA WPA],
        %w[WPA2 WPA],
        %w[WPA3 WPA],
        %w[WEP WEP],
        [nil,    'WPA'],
      ].each do |input_security, expected_qr_security|
        it "generates correct QR string for #{input_security || 'open network'}" do
          allow(subject).to receive(:connection_security_type).and_return(input_security)
          expected_qr_string = "WIFI:T:#{expected_qr_security};S:TestNetwork;P:test_password;H:false;;"

          silence_output { subject.generate_qr_code }

          expect(subject).to have_received(:run_os_command)
            .with(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
        end
      end

      it 'defaults to WPA when security type is unknown but password exists' do
        allow(subject).to receive(:connection_security_type).and_return('RSN')
        expected_qr_string = 'WIFI:T:WPA;S:TestNetwork;P:test_password;H:false;;'

        silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_os_command)
          .with(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
      end
    end

    context 'when escaping special characters' do
      [
        ['Network;With;Semicolons', 'password,with,commas',
          'WIFI:T:WPA;S:Network\;With\;Semicolons;P:password\,with\,commas;H:false;;'],
        ['Network:With:Colons', 'password:with:colons',
          'WIFI:T:WPA;S:Network\:With\:Colons;P:password\:with\:colons;H:false;;'],
        ['Network\With\Backslashes', 'pass\word',
          'WIFI:T:WPA;S:Network\\\\With\\\\Backslashes;P:pass\\\\word;H:false;;'],
        ['Regular-Network_Name', 'regularPassword123',
          'WIFI:T:WPA;S:Regular-Network_Name;P:regularPassword123;H:false;;'],
      ].each do |test_network, test_password, expected_qr_string|
        it "properly escapes special characters in '#{test_network}' / '#{test_password}'" do
          allow(subject).to receive_messages(
            connected_network_name:     test_network,
            connected_network_password: test_password
          )

          silence_output { subject.generate_qr_code }

          safe_network_name = test_network.gsub(/[^\w\-_]/, '_')
          expected_filename = "#{safe_network_name}-qr-code.png"

          expect(subject).to have_received(:run_os_command)
            .with(satisfy do |cmd|
              staged_prefix = "./#{expected_filename.delete_suffix('.png')}-"
              cmd.first(2) == %w[qrencode -o] &&
                cmd[2].start_with?(staged_prefix) &&
                cmd[2].end_with?('.png') &&
                cmd.last == expected_qr_string
            end)
        end
      end
    end

    context 'when generating filenames' do
      [
        ['SimpleNetwork',       'SimpleNetwork-qr-code.png'],
        ['Network With Spaces', 'Network_With_Spaces-qr-code.png'],
        ['Network@#$%^&*()!',   'Network__________-qr-code.png'],
        ['cafe-reseau',         'cafe-reseau-qr-code.png'],
      ].each do |input_name, expected_filename|
        it "generates safe filename for '#{input_name}'" do
          allow(subject).to receive(:connected_network_name).and_return(input_name)

          result = silence_output { subject.generate_qr_code }

          expect(result).to eq(expected_filename)
        end
      end
    end

    context 'when handling open networks' do
      it 'generates QR code for open network (no password)' do
        allow(subject).to receive_messages(connected_network_password: nil, connection_security_type: nil)
        expected_qr_string = 'WIFI:T:nopass;S:TestNetwork;P:;H:false;;'

        result = silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_os_command)
          .with(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
        expect(result).to eq('TestNetwork-qr-code.png')
      end
    end

    context 'when handling errors' do
      it 'raises WifiWand::Error when qrencode command fails' do
        allow(subject).to receive(:run_os_command)
          .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'qrencode', 'Command failed'))

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error, /Failed to generate QR code/)
      end
    end
  end
end
