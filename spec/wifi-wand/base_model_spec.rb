# frozen_string_literal: true

require_relative '../../lib/wifi-wand/operating_systems'
require_relative '../../lib/wifi-wand/models/ubuntu_model'
require_relative '../../lib/wifi-wand/models/mac_os_model'

describe 'Common WiFi Model Behavior (All OS)' do
  subject { uses_real_env? ? build_real_test_model : build_fake_base_model }

  def queued_response(*values)
    remaining = values.dup

    ->(_model = nil) do
      current = remaining.length > 1 ? remaining.shift : remaining.first
      raise current if current.is_a?(Exception)

      current
    end
  end

  def build_real_test_model(options = {})
    create_test_model(options)
  end

  def build_fake_base_model(options = {})
    model = WifiWandSpecSupport::Fakes::FakeBaseModel.new({ verbose: false }.merge(options))
    model.command_executor = WifiWandSpecSupport::Fakes::FakeCommandExecutor.new(
      default_result: command_result(stdout: '')
    )
    model.connectivity_tester = WifiWandSpecSupport::Fakes::FakeConnectivityTester.new
    model.init
    allow(model.connection_manager).to receive(:sleep)
    model
  end


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
      result = subject.wifi_info
      expect(result).to be_a(Hash)

      # All OSes must provide these fields with consistent types
      expect(result).to include(
        'wifi_on', 'internet_tcp_connectivity', 'dns_working', 'captive_portal_state',
        'internet_connectivity_state', 'interface', 'default_interface', 'connected', 'network',
        'ssid_identity_available', 'ssid_identity_status', 'ssid_identity_warning', 'ip_address',
        'mac_address', 'nameservers', 'timestamp'
      )

      expect([true, false]).to include(result['wifi_on'])
      expect([true, false, nil]).to include(result['connected'])
      expect([true, false]).to include(result['ssid_identity_available'])
      expect(%w[available unavailable not_connected unknown]).to include(result['ssid_identity_status'])
      expect([true, false]).to include(result['internet_tcp_connectivity'])
      expect([true, false]).to include(result['dns_working'])
      expect(%i[free present indeterminate]).to include(result['captive_portal_state'])
      expect(%i[reachable unreachable indeterminate]).to include(result['internet_connectivity_state'])
      expect(result['timestamp']).to be_a(Time)
    end

    it 'does not include preferred or available network lists' do
      result = subject.wifi_info

      expect(result).not_to have_key('preferred_networks')
      expect(result).not_to have_key('available_networks')
    end

    it 'returns nil when default_interface lookup fails' do
      subject.set_response(:default_interface, WifiWand::Error.new('default route unavailable'))

      result = subject.wifi_info

      expect(result).to be_a(Hash)
      expect(result['default_interface']).to be_nil
    end

    it 'returns nil when mac_address lookup fails' do
      subject.set_response(:mac_address, WifiWand::Error.new('mac lookup unavailable'))

      result = subject.wifi_info

      expect(result).to be_a(Hash)
      expect(result['mac_address']).to be_nil
    end

    it 'returns empty array when nameservers lookup fails' do
      subject.set_response(:nameservers, WifiWand::Error.new('dns config unavailable'))

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
    subject(:model) { build_fake_base_model }

    it 'raises a dedicated error when the interface remains associated' do
      model.connected_network_name_state = 'TestNet'
      model.set_response(:wait_until_disassociated!, wait_timeout_error(action: :disassociated, timeout: 5))

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'reports wifi status command failures as disconnection errors' do
      model.set_response(:wifi_on?, os_command_error(
        exitstatus: 1,
        command:    'networksetup -getairportpower en0',
        text:       'permission denied'
      ))

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('permission denied')
        expect(error.reason).to include('networksetup -getairportpower en0')
      end
      expect(model.disconnect_calls).to be_empty
    end

    it 'attempts disconnect when association cannot be determined before the command' do
      model.set_response(
        :connected_network_name,
        WifiWand::MacOsRedactionError.new(operation_description: 'Current WiFi network queries')
      )
      model.set_response(:_disconnect, os_command_error(
        exitstatus: 1,
        command:    'disconnect current network',
        text:       'disconnect failed'
      ))

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('disconnect failed')
        expect(error.reason).to include('disconnect current network')
      end
      expect(model.disconnect_calls.length).to eq(1)
      expect(model.wait_until_disassociated_calls).to be_empty
    end

    it 'reports secondary connection probe command failures as disconnection errors' do
      model.connected_network_name_state = nil
      model.connected_state = false
      model.set_response(:connected?, os_command_error(
        exitstatus: 1,
        command:    'nmcli connection show --active',
        text:       'NetworkManager unavailable'
      ))

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('NetworkManager unavailable')
        expect(error.reason).to include('nmcli connection show --active')
      end
      expect(model.disconnect_calls).to be_empty
    end

    it 'reports verification probe command failures as disconnection errors' do
      model.connected_network_name_state = 'TestNet'
      model.set_response(:wait_until_disassociated!, os_command_error(
        exitstatus: 1,
        command:    'nmcli connection show --active',
        text:       'probe failed during verification'
      ))

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to eq('TestNet')
        expect(error.reason).to include('probe failed during verification')
        expect(error.reason).to include('nmcli connection show --active')
      end
    end

    it 'raises when disassociation is not stable after the initial wait succeeds' do
      model.connected_network_name_state = 'TestNet'
      model.set_response(:disassociated_stable?, false)
      model.set_response(:disconnect_stability_window_in_secs, 0.1)

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'is a no-op when wifi is already disassociated' do
      model.connected_network_name_state = nil
      model.connected_state = false

      expect(model.disconnect).to be_nil
      expect(model.disconnect_calls).to be_empty
      expect(model.wait_until_disassociated_calls).to be_empty
    end
  end

  # No real-environment test for #disconnect.
  #
  # macOS's airportd daemon reconnects to preferred networks within
  # milliseconds of a CoreWLAN programmatic disassociation, making a
  # stable post-disconnect state impossible to observe. Every attempt
  # landed in the NetworkDisconnectionError branch; the clean-disconnect
  # path was never reachable. No public API suppresses airportd's
  # reconnect behavior without side effects (e.g. removing from preferred
  # networks causes reconnection to a different preferred network).
  #
  # The disconnect logic is fully covered by the mocked unit tests above.
  # See dev/docs/TESTING.md for the full investigation and decision record.

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
      subject.wifi_on_state = true

      subject.wifi_on
      expect(subject.command_executor.run_calls).to be_empty
    end

    # No real-environment test for #wifi_on on macOS.
    # On macOS, airportd auto-reconnects within milliseconds of any WiFi toggle,
    # causing the suite's global restore hook to race airportd and produce
    # -3900 / tmpErr errors. This constraint is macOS-specific.
    # See dev/docs/TESTING.md for the full investigation and decision record.
  end

  describe '#wifi_off' do
    it 'does nothing when wifi is already off' do
      subject.wifi_on_state = false

      subject.wifi_off
      expect(subject.command_executor.run_calls).to be_empty
    end

    # No real-environment test for #wifi_off on macOS.
    # Same airportd reconnect race as #wifi_on above.
    # See dev/docs/TESTING.md for the full investigation and decision record.
  end

  describe '#cycle_network' do
    context 'when wifi starts on' do
      before do
        subject.wifi_on_state = true
      end

      it 'calls wifi_off then wifi_on in sequence' do
        subject.cycle_network

        expect(subject.power_transitions).to eq(%i[wifi_off wifi_on])
      end
    end

    context 'when wifi starts off' do
      before do
        subject.wifi_on_state = false
      end

      it 'calls wifi_on then wifi_off in sequence' do
        subject.cycle_network

        expect(subject.power_transitions).to eq(%i[wifi_on wifi_off])
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

      # No real-environment test for 'WiFi is already off' or ':wifi_on timeout'
      # on macOS: both call wifi_off and leave WiFi off, triggering the airportd
      # reconnect race in the restore hook. macOS-specific; see TESTING.md.

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
        allow_any_instance_of(WifiWand::StatusWaiter).to receive(:sleep)
      end

      it 'returns nil immediately for :associated when already associated' do
        subject.connected_network_name_state = 'TestNetwork1'

        expect(subject.till(:associated)).to be_nil
      end

      it 'returns nil immediately for :disassociated when already disassociated' do
        subject.connected_network_name_state = nil

        expect(subject.till(:disassociated)).to be_nil
      end

      it 'waits for :associated until association is observed' do
        subject.set_response(:connected_network_name, queued_response(nil, nil, 'TestNetwork1'))

        expect(
          subject.till(:associated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        ).to be_nil
      end

      it 'waits for :disassociated until association clears' do
        subject.set_response(:connected_network_name, queued_response('TestNetwork1', 'TestNetwork1', nil))

        expect(
          subject.till(:disassociated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        ).to be_nil
      end

      it 'raises WaitTimeoutError for :associated when association never appears' do
        subject.connected_network_name_state = nil
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1000.0, 1001.1)

        expect do
          subject.till(:associated, timeout_in_secs: 1, wait_interval_in_secs: 0)
        end.to raise_error(WifiWand::WaitTimeoutError)
      end

      it 'raises WaitTimeoutError for :disassociated when association never clears' do
        subject.connected_network_name_state = 'TestNetwork1'
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


  # Ordinary context - model-level WiFi-on state without changing the host radio.
  context 'when wifi starts on' do
    before do
      subject.wifi_on_state = true
    end

    it_behaves_like 'interface commands complete without error'
  end

  # Ordinary context - model-level WiFi-off state without changing the host radio.
  context 'when wifi starts off' do
    before do
      subject.wifi_on_state = false
      subject.connected_state = false
      subject.connected_network_name_state = nil
    end

    it_behaves_like 'interface commands complete without error'

    it 'raises WiFi-off errors for radio-dependent queries' do
      expect { subject.available_network_names }.to raise_error(WifiWand::WifiOffError)
      expect { subject.connected_network_name }.to raise_error(WifiWand::WifiOffError)
    end

    it 'reports unavailable connection details without raising' do
      info = subject.wifi_info

      expect(info['wifi_on']).to be(false)
      expect(info['network']).to be_nil
      expect(info['ip_address']).to be_nil
    end
  end

  # Real-environment read-write contexts
  context 'when wifi starts on (real environment)', :real_env_read_write do
    before { subject.wifi_on }

    it_behaves_like 'interface commands complete without error'

    it 'can query connected network name' do
      expect(subject.connected_network_name).to be_a(String).or be_nil
    end
  end

  # No real-environment context for 'when wifi starts off' on macOS.
  # The before hook calls wifi_off, leaving WiFi off at test end, which
  # triggers the airportd reconnect race in the restore hook. macOS-specific;
  # see dev/docs/TESTING.md.

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
      subject.connected_state = true
      subject.connected_network_name_state = 'TestNetwork'

      expect(subject.restore_network_state(valid_state)).to eq(:already_connected)
    end
  end

  describe '#init_wifi_interface' do
    context 'when provided interface is valid' do
      it 'uses the provided wifi interface' do
        options = { wifi_interface: 'wlan1', verbose: false }
        model = subject.class.new(options)
        model.valid_wifi_interfaces = %w[wlan0 wlan1 en0]

        model.init_wifi_interface
        expect(model.wifi_interface).to eq('wlan1')
      end
    end

    context 'when provided interface is invalid' do
      it 'raises InvalidInterfaceError' do
        options = { wifi_interface: 'invalid0', verbose: false }
        model = subject.class.new(options)
        model.valid_wifi_interfaces = %w[wlan0 wlan1 en0]

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

      inst = test_class.new
      expect(inst.os).to eq(:mac)
      expect(inst.mac?).to be true
      expect(inst.ubuntu?).to be false
    end
  end

  describe '#public_ip_address error handling' do
    it 'raises PublicIPLookupError when response is not success' do
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
      base_model_instance = WifiWand::BaseModel.new

      expect do
        base_model_instance.default_interface
      end.to raise_error(NotImplementedError, /must implement default_interface/)
    end
  end

  describe '#wifi_info exception handling' do
    before do
      subject.wifi_on_state = true
      subject.connected_network_name_state = 'TestNet'
      subject.connected_state = true
      subject.ip_address_state = '192.168.1.100'
      subject.default_interface_state = 'wlan0'
      subject.mac_address_state = 'aa:bb:cc:dd:ee:ff'
      subject.nameservers_state = ['8.8.8.8']
    end

    it 'handles internet_tcp_connectivity exceptions' do
      subject.connectivity_tester.tcp_result = SocketError.new('Network error')
      subject.connectivity_tester.dns_result = true

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
      subject.connectivity_tester.tcp_result = true
      subject.connectivity_tester.dns_result = SocketError.new('DNS error')

      result = subject.wifi_info
      expect(result['dns_working']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
    end

    it 'does not call captive_portal_state when TCP fails' do
      subject.connectivity_tester.tcp_result = false
      subject.connectivity_tester.dns_result = true
      subject.connectivity_tester.captive_result = -> do
        raise 'captive_portal_state should not be called when TCP fails'
      end

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'does not call captive_portal_state when DNS fails' do
      subject.connectivity_tester.tcp_result = true
      subject.connectivity_tester.dns_result = false
      subject.connectivity_tester.captive_result = -> do
        raise 'captive_portal_state should not be called when DNS fails'
      end

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'does not call captive_portal_state when both TCP and DNS fail' do
      subject.connectivity_tester.tcp_result = false
      subject.connectivity_tester.dns_result = false
      subject.connectivity_tester.captive_result = -> do
        raise 'captive_portal_state should not be called when TCP and DNS fail'
      end

      result = subject.wifi_info
      expect(result['captive_portal_state']).to eq(:indeterminate)
    end

    it 'calls captive_portal_state when both TCP and DNS succeed' do
      subject.connectivity_tester.tcp_result = true
      subject.connectivity_tester.dns_result = true
      subject.connectivity_tester.captive_result = :free

      expect(subject.wifi_info['captive_portal_state']).to eq(:free)
    end
  end

  describe '#connected_to?' do
    it 'returns true when connected to specified network' do
      subject.connected_network_name_state = 'TestNetwork'

      expect(subject.connected_to?('TestNetwork')).to be true
    end

    it 'returns false when connected to different network' do
      subject.connected_network_name_state = 'OtherNetwork'

      expect(subject.connected_to?('TestNetwork')).to be false
    end

    it 'returns false when not connected to any network' do
      subject.connected_network_name_state = nil

      expect(subject.connected_to?('TestNetwork')).to be false
    end
  end

  describe '#remove_preferred_networks' do
    before do
      subject.preferred_networks_state = %w[Network1 Network2 Network3]
      subject.set_response(:remove_preferred_network) { |_model, _network_name| nil }
    end

    it 'handles array as first argument' do
      networks_to_remove = %w[Network1 Network2]
      subject.remove_preferred_networks(networks_to_remove)

      expect(subject.removed_preferred_networks).to include('Network1', 'Network2')
    end

    it 'handles multiple string arguments' do
      subject.remove_preferred_networks('Network1', 'Network2')

      expect(subject.removed_preferred_networks).to include('Network1', 'Network2')
    end

    it 'ignores non-existent networks' do
      subject.remove_preferred_networks('Network1', 'NonExistent')

      expect(subject.removed_preferred_networks).to include('Network1')
      expect(subject.removed_preferred_networks).not_to include('NonExistent')
    end

    it 'uses has_preferred_network? instead of exact preferred_network string matches' do
      subject.preferred_networks_state = %w[Network1 AliasForNetwork2]

      subject.remove_preferred_networks('Network1', 'AliasForNetwork2', 'NonExistent')

      expect(subject.removed_preferred_networks).to include('Network1', 'AliasForNetwork2')
      expect(subject.removed_preferred_networks).not_to include('NonExistent')
    end

    it 'returns the actual deleted profile names reported by the model' do
      subject.preferred_networks_state = ['Network1']
      subject.set_response(:remove_preferred_network) do |_model, network_name|
        network_name == 'Network1' ? ['Network1', 'Network1 1'] : nil
      end

      expect(subject.remove_preferred_networks('Network1', 'NonExistent')).to eq(['Network1', 'Network1 1'])
    end

    it 'falls back to the requested network name when a model returns nil' do
      subject.preferred_networks_state = ['Network1']

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
    let(:progress_callback) { ->(_data) {} }

    it 'delegates to StatusLineDataBuilder with the current model context' do
      expect(WifiWand::StatusLineDataBuilder).to receive(:call).with(
        subject,
        hash_including(
          progress_callback:       progress_callback,
          runtime_config:          subject.runtime_config,
          expected_network_errors: WifiWand::BaseModel::EXPECTED_NETWORK_ERRORS
        )
      ).and_return({})

      subject.status_line_data(progress_callback: progress_callback)
    end

    it 'returns the builder result unchanged' do
      allow(WifiWand::StatusLineDataBuilder).to receive(:call).and_return({ wifi_on: true })

      expect(subject.status_line_data).to eq(wifi_on: true)
    end
  end

  describe 'runtime configuration propagation' do
    subject(:model) { runtime_model_class.new(options) }

    def with_redirected_stdout(stream)
      original_stdout = $stdout
      $stdout = stream
      yield
    ensure
      $stdout = original_stdout
    end

    let(:runtime_model_class) do
      Class.new(WifiWand::BaseModel) do
        def self.os_id = :test

        def _available_network_names = []
        def _connected_network_name = nil
        def _connect(_network_name, _password = nil) = nil
        def _disconnect = nil
        def _ip_address = nil
        def _preferred_network_password(_network_name) = nil

        def connected? = false
        def connection_security_type = 'NONE'
        def default_interface = nil
        def is_wifi_interface?(_interface_name) = true
        def mac_address = nil
        def nameservers = []
        def network_hidden? = false
        def open_resource(_resource) = nil
        def probe_wifi_interface = 'wlan0'
        def preferred_networks = []
        def remove_preferred_network(_network_name) = nil
        # rubocop:disable Naming/AccessorMethodName
        def set_nameservers(_nameservers) = nil
        # rubocop:enable Naming/AccessorMethodName
        def validate_os_preconditions = nil
        def wifi_off = nil
        def wifi_on = nil
        def wifi_on? = true
      end
    end

    let(:initial_verbose) { false }
    let(:initial_out_stream) { StringIO.new }
    let(:options) { { verbose: initial_verbose, out_stream: initial_out_stream } }

    it 'applies verbose mode changes to helper services after initialization' do
      expect(model.connection_manager.verbose?).to be(false)

      model.status_waiter.wait_for(:wifi_on, timeout_in_secs: 0.01)
      expect(initial_out_stream.string).to eq('')

      model.verbose = true
      expect(model.connection_manager.verbose?).to be(true)

      model.status_waiter.wait_for(:wifi_on, timeout_in_secs: 0.01)

      expect(initial_out_stream.string).to include('StatusWaiter (wifi_on): starting')
      expect(initial_out_stream.string).to include('completed without needing to wait')
    end

    it 'pins the default out_stream at initialization when none is explicitly configured' do
      initial_stdout = StringIO.new
      redirected_output = StringIO.new
      runtime_model = nil

      with_redirected_stdout(initial_stdout) do
        runtime_model = runtime_model_class.new(verbose: true)
      end

      with_redirected_stdout(redirected_output) do
        runtime_model.status_waiter.wait_for(:wifi_on, timeout_in_secs: 0.01)
        runtime_model.run_command_using_args(['bash', '-lc', 'printf runtime-config-test'])
      end

      expect(initial_stdout.string).to include('StatusWaiter (wifi_on): starting')
      expect(initial_stdout.string).to include('Command: bash -lc printf runtime-config-test')
      expect(redirected_output.string).to eq('')
    end

    it 'preserves initialization-time out_stream behavior for helper services' do
      explicit_output = StringIO.new
      redirected_output = StringIO.new
      runtime_model = runtime_model_class.new(verbose: true, out_stream: explicit_output)

      with_redirected_stdout(redirected_output) do
        runtime_model.status_waiter.wait_for(:wifi_on, timeout_in_secs: 0.01)
        runtime_model.run_command_using_args(['bash', '-lc', 'printf configured-stream-test'])
      end

      expect(explicit_output.string).to include('StatusWaiter (wifi_on): starting')
      expect(explicit_output.string).to include('Command: bash -lc printf configured-stream-test')
      expect(redirected_output.string).to eq('')
    end
  end

  describe 'private methods' do
    describe '#connected_network_password' do
      it 'returns nil when not connected to any network' do
        subject.connected_network_name_state = nil

        result = subject.send(:connected_network_password)
        expect(result).to be_nil
      end

      it 'returns password for connected network' do
        network_name = 'TestNetwork'
        expected_password = 'test_password'

        subject.connected_network_name_state = network_name
        subject.preferred_networks_state = [network_name]
        subject.preferred_network_passwords = { network_name => expected_password }

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
      subject.command_executor.command_available_result = true
      subject.command_executor.run_result = command_result(stdout: '')
      subject.connected_network_name_state = network_name
      subject.connected_state = true
      subject.connection_security_type_state = security_type
      subject.network_hidden_state = false
      subject.preferred_networks_state = [network_name]
      subject.preferred_network_passwords = { network_name => network_password }
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
          subject.command_executor.command_available_result = false
          allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: os_id))

          expect do
            silence_output do
              subject.generate_qr_code
            end
          end.to raise_error(WifiWand::Error, /#{Regexp.escape(expected_command)}/)
        end
      end

      it 'raises error with generic message for unknown OS' do
        subject.command_executor.command_available_result = false
        allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(double('os', id: :unknown))

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error,
            /install qrencode using your system package manager/)
      end
    end

    context 'when validating network connection' do
      it 'raises error when not connected to any network' do
        subject.connected_network_name_state = nil

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
          subject.connection_security_type_state = input_security
          expected_qr_string = "WIFI:T:#{expected_qr_security};S:TestNetwork;P:test_password;H:false;;"

          silence_output { subject.generate_qr_code }

          expect(subject.command_executor.run_calls.last[:command])
            .to(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
        end
      end

      it 'defaults to WPA when security type is unknown but password exists' do
        subject.connection_security_type_state = 'RSN'
        expected_qr_string = 'WIFI:T:WPA;S:TestNetwork;P:test_password;H:false;;'

        silence_output { subject.generate_qr_code }

        expect(subject.command_executor.run_calls.last[:command])
          .to(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
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
          subject.connected_network_name_state = test_network
          subject.preferred_networks_state = [test_network]
          subject.preferred_network_passwords = { test_network => test_password }

          silence_output { subject.generate_qr_code }

          safe_network_name = test_network.gsub(/[^\w\-_]/, '_')
          expected_filename = "#{safe_network_name}-qr-code.png"

          expect(subject.command_executor.run_calls.last[:command]).to satisfy do |cmd|
            staged_prefix = "./#{expected_filename.delete_suffix('.png')}-"
            cmd.first(2) == %w[qrencode -o] &&
              cmd[2].start_with?(staged_prefix) &&
              cmd[2].end_with?('.png') &&
              cmd.last == expected_qr_string
          end
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
          subject.connected_network_name_state = input_name
          subject.preferred_networks_state = [input_name]
          subject.preferred_network_passwords = { input_name => network_password }

          result = silence_output { subject.generate_qr_code }

          expect(result).to eq(expected_filename)
        end
      end
    end

    context 'when handling open networks' do
      it 'generates QR code for open network (no password)' do
        subject.preferred_network_passwords = { 'TestNetwork' => nil }
        subject.connection_security_type_state = nil
        expected_qr_string = 'WIFI:T:nopass;S:TestNetwork;P:;H:false;;'

        result = silence_output { subject.generate_qr_code }

        expect(subject.command_executor.run_calls.last[:command])
          .to(satisfy { |cmd| cmd.first(2) == %w[qrencode -o] && cmd.last == expected_qr_string })
        expect(result).to eq('TestNetwork-qr-code.png')
      end
    end

    context 'when handling errors' do
      it 'raises WifiWand::Error when qrencode command fails' do
        subject.command_executor.run_result = os_command_error(
          exitstatus: 1,
          command:    'qrencode',
          text:       'Command failed'
        )

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error, /Failed to generate QR code/)
      end
    end
  end
end
