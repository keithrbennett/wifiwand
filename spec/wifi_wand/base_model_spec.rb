# frozen_string_literal: true

require_relative '../../lib/wifi_wand/platforms/selector'
require_relative '../../lib/wifi_wand/platforms/ubuntu/model'
require_relative '../../lib/wifi_wand/platforms/mac/model'

describe 'Common WiFi Model Behavior (All OS)' do
  # Mock OS calls to prevent real system interaction during ordinary tests
  # Automatically instantiate the correct model for the current OS
  subject { create_test_model }

  before do
    # Mock all OS-calling methods to prevent real system calls in ordinary tests
    # Only skip these mocks for examples that intentionally use the real environment.
    # Use RSpec.current_example to get the current running example
    unless uses_real_env?
      # Also mock the underlying NetworkConnectivityTester to prevent real network calls
      tester = subject.connectivity_tester
      allow(tester).to receive_messages(
        tcp_connectivity?:             true,
        dns_working?:                  true,
        captive_portal_login_required: :no
      )
      allow(subject.connection_manager).to receive(:wait_for_connection_activation)

      # Mock low-level OS command execution to prevent real system calls
      # but allow higher-level methods to be called for testing
      allow(subject).to receive_messages(
        wifi_on?:                   true,
        available_network_names:    %w[TestNetwork1 TestNetwork2],
        connected_network_name:     'TestNetwork1',
        bssid:                      '00:11:22:33:44:55',
        signal_quality:             WifiWand::SignalQuality.new(value: 72, unit: :percent),
        ipv4_addresses:             ['192.168.1.100'],
        ipv6_addresses:             ['2001:db8::100'],
        mac_address:                'aa:bb:cc:dd:ee:ff',
        default_interface:          'wlan0',
        nameservers:                ['8.8.8.8', '8.8.4.4'],
        preferred_networks:         %w[TestNetwork1 SavedNetwork1],
        internet_tcp_connectivity?: true,
        dns_working?:               true,
        run_command:                command_result(stdout: ''),
        till:                       nil
      )
    end
  end

  describe '#command_available?' do
    it 'is public so model helpers can check optional dependencies without send' do
      command_executor = instance_double(WifiWand::CommandExecutor)
      subject.command_executor = command_executor

      expect(command_executor).to receive(:command_available?).with('qrencode').and_return(true)

      expect(subject.public_methods).to include(:command_available?)
      expect(subject.private_methods).not_to include(:command_available?)
      expect(subject.command_available?('qrencode')).to be(true)
    end
  end

  describe '#internet_tcp_connectivity?' do
    it 'returns boolean indicating TCP connectivity' do
      expect(subject.internet_tcp_connectivity?).to be(true).or be(false)
    end
  end

  describe '#dns_working?' do
    it 'returns boolean indicating DNS resolution capability' do
      expect(subject.dns_working?).to be(true).or be(false)
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
        'wifi_on', 'internet_tcp_connectivity', 'dns_working', 'captive_portal_login_required',
        'internet_connectivity_state', 'interface', 'default_interface', 'connected', 'network',
        'bssid', 'signal_quality', 'ssid_identity_available', 'ssid_identity_status', 'ssid_identity_warning',
        'ipv4_addresses', 'ipv6_addresses', 'mac_address', 'nameservers', 'timestamp'
      )

      expect(result['wifi_on']).to be(true).or be(false)
      expect(result['connected']).to satisfy do |value|
        [true, false, nil].include?(value)
      end
      expect(result['signal_quality']).to eq(value: 72, unit: :percent)
      expect(result['ssid_identity_available']).to be(true).or be(false)
      expect(result['ssid_identity_status']).to satisfy do |value|
        %w[available unavailable not_connected unknown].include?(value)
      end
      expect(result['internet_tcp_connectivity']).to be(true).or be(false)
      expect(result['dns_working']).to be(true).or be(false)
      expect(result['captive_portal_login_required']).to satisfy do |value|
        %i[yes no unknown].include?(value)
      end
      expect(result['internet_connectivity_state']).to satisfy do |value|
        %i[reachable unreachable indeterminate].include?(value)
      end
      expect(result['timestamp']).to be_a(Time)
    end

    it 'does not include preferred or available network lists' do
      result = subject.wifi_info

      expect(result).not_to have_key('preferred_networks')
      expect(result).not_to have_key('available_networks')
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

    it 'starts TCP and DNS connectivity probes before waiting for either result' do
      dns_started_mutex = Mutex.new
      dns_started_condition = ConditionVariable.new
      dns_started = false

      allow(subject).to receive(:internet_tcp_connectivity?) do
        dns_started_mutex.synchronize do
          dns_started_condition.wait(dns_started_mutex, 5) unless dns_started
          raise 'DNS probe did not start while TCP probe was still running' unless dns_started
        end

        true
      end
      allow(subject).to receive(:dns_working?) do
        dns_started_mutex.synchronize do
          dns_started = true
          dns_started_condition.broadcast
        end

        true
      end

      expect(subject.wifi_info['internet_connectivity_state']).to eq(:reachable)
    end
  end

  describe '#wifi_on?' do
    it 'returns boolean indicating wifi status' do
      expect(subject.wifi_on?).to be(true).or be(false)
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

  describe '#ipv4_addresses' do
    it 'returns a non-empty array of IPv4 addresses when an address is available' do
      expect(subject.ipv4_addresses).to be_a_non_empty_array_of_ip_addresses
    end
  end

  describe '#ipv6_addresses' do
    it 'returns an array of IPv6 addresses when available' do
      expect(subject.ipv6_addresses).to eq(['2001:db8::100'])
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
      klass = Class.new(WifiWand::BaseModel) do
        def self.os_id = :mac
      end

      define_base_model_required_methods(klass, probe_wifi_interface: 'en0')
    end

    it 'raises a dedicated error when the interface remains associated' do
      allow(model).to receive_messages(
        wifi_on?:               true,
        connected_network_name: 'TestNet'
      )
      allow(model).to receive(:_disconnect)
      allow(model).to receive(:wait_until_disassociated!)
        .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'reports wifi status command failures as disconnection errors' do
      allow(model).to receive(:wifi_on?)
        .and_raise(os_command_error(
          exitstatus: 1,
          command:    'networksetup -getairportpower en0',
          text:       'permission denied'
        ))
      allow(model).to receive(:_disconnect)

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('permission denied')
        expect(error.reason).to include('networksetup -getairportpower en0')
      end
      expect(model).not_to have_received(:_disconnect)
    end

    it 'attempts disconnect when association cannot be determined before the command' do
      allow(model).to receive(:wifi_on?).and_return(true)
      allow(model).to receive(:connected_network_name)
        .and_raise(WifiWand::Error, 'association unavailable')
      allow(model).to receive(:wait_until_disassociated!)
      allow(model).to receive(:_disconnect)
        .and_raise(os_command_error(
          exitstatus: 1,
          command:    'disconnect current network',
          text:       'disconnect failed'
        ))

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('disconnect failed')
        expect(error.reason).to include('disconnect current network')
      end
      expect(model).to have_received(:_disconnect)
      expect(model).not_to have_received(:wait_until_disassociated!)
    end

    it 'reports secondary connection probe command failures as disconnection errors' do
      allow(model).to receive_messages(wifi_on?: true, connected_network_name: nil)
      allow(model).to receive(:connected?)
        .and_raise(os_command_error(
          exitstatus: 1,
          command:    'nmcli connection show --active',
          text:       'NetworkManager unavailable'
        ))
      allow(model).to receive(:_disconnect)

      expect { model.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('NetworkManager unavailable')
        expect(error.reason).to include('nmcli connection show --active')
      end
      expect(model).not_to have_received(:_disconnect)
    end

    it 'reports verification probe command failures as disconnection errors' do
      allow(model).to receive_messages(wifi_on?: true, connected_network_name: 'TestNet')
      allow(model).to receive(:_disconnect)
      allow(model).to receive(:wait_until_disassociated!)
        .and_raise(os_command_error(
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
      allow(model).to receive_messages(
        wifi_on?:                            true,
        connected_network_name:              'TestNet',
        disconnect_stability_window_in_secs: 0.1
      )
      allow(model).to receive(:_disconnect)
      allow(model).to receive_messages(wait_until_disassociated!: nil, disassociated_stable?: false)

      expect { model.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'is a no-op when wifi is already disassociated' do
      allow(model).to receive_messages(wifi_on?: true, connected_network_name: nil, connected?: false)
      allow(model).to receive(:wait_until_disassociated!)
      allow(model).to receive(:_disconnect)

      expect(model.disconnect).to be_nil
      expect(model).not_to have_received(:_disconnect)
      expect(model).not_to have_received(:wait_until_disassociated!)
    end
  end

  describe '#connection_ready?' do
    it 'logs lookup failures in verbose mode and returns false' do
      output = StringIO.new
      test_model_class = Class.new(WifiWand::BaseModel) do
        def self.os_id = :mac
      end
      define_base_model_required_methods(test_model_class, probe_wifi_interface: 'en0')
      model = test_model_class.new(verbose: true, out_stream: output)

      allow(model).to receive(:connected?).and_raise(WifiWand::Error, 'state probe failed')

      expect(model.connection_ready?('TestNet')).to be(false)
      expect(output.string).to include('connection_ready? check failed: WifiWand::Error: state probe failed')
    end
  end

  describe '#disconnect_stability_window_in_secs' do
    it 'defaults to two ordinary wait intervals' do
      expect(subject.disconnect_stability_window_in_secs)
        .to eq(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL * 2)
    end
  end

  describe '#disassociated_stable?' do
    it 'returns true once the interface stays disassociated through the stability window' do
      allow(subject).to receive_messages(
        disconnect_stability_window_in_secs: 0.2,
        disconnect_association_state:        { associated: false, network_name: nil }
      )
      allow(subject).to receive(:monotonic_now).and_return(10.0, 10.1, 10.2)
      allow(subject).to receive(:sleep)

      expect(subject.disassociated_stable?).to be(true)
      expect(subject).to have_received(:sleep).with(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL).once
    end

    it 'returns false when the interface is still associated at the start of the stability window' do
      allow(subject).to receive_messages(
        disconnect_stability_window_in_secs: 0.2,
        disconnect_association_state:        { associated: true, network_name: 'TestNet' }
      )
      allow(subject).to receive(:monotonic_now).and_return(10.0)
      allow(subject).to receive(:sleep)

      expect(subject.disassociated_stable?).to be(false)
      expect(subject).not_to have_received(:sleep)
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

  describe '#associated?' do
    it 'returns false when the connected network lookup raises a wifi-wand error' do
      allow(subject).to receive(:connected_network_name).and_raise(WifiWand::Error, 'SSID unavailable')

      expect(subject.associated?).to be(false)
    end

    it 'returns a boolean', :real_env_read_only do
      expect(subject.associated?).to be(true).or be(false)
    end

    it 'is true when wifi is on and a non-empty network name is present', :real_env_read_only do
      skip 'WiFi is currently off' unless subject.wifi_on?

      name = subject.connected_network_name
      skip 'No visible network name is currently available' if name.nil? || name.empty?

      expect(subject.associated?).to be(true)
    end
  end

  describe '#wifi_on' do
    it 'does nothing when wifi is already on' do
      allow(subject).to receive(:wifi_on?).and_return(true)
      allow(subject).to receive(:run_command)
      allow(subject).to receive(:till) # Mock the status waiter

      subject.wifi_on
      expect(subject).not_to have_received(:run_command)
    end

    # No real-environment test for #wifi_on on macOS.
    # On macOS, airportd auto-reconnects within milliseconds of any WiFi toggle,
    # causing the suite's global restore hook to race airportd and produce
    # -3900 / tmpErr errors. This constraint is macOS-specific.
    # See dev/docs/TESTING.md for the full investigation and decision record.
  end

  describe '#wifi_off' do
    it 'does nothing when wifi is already off' do
      allow(subject).to receive(:wifi_on?).and_return(false)
      allow(subject).to receive(:run_command)
      allow(subject).to receive(:till) # Mock the status waiter

      subject.wifi_off
      expect(subject).not_to have_received(:run_command)
    end

    # No real-environment test for #wifi_off on macOS.
    # Same airportd reconnect race as #wifi_on above.
    # See dev/docs/TESTING.md for the full investigation and decision record.
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
      let(:association_wait_interval) { 0.1 }

      before do
        allow(subject).to receive(:till).and_call_original
        allow(subject.status_waiter).to receive(:sleep)
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
          subject.till(
            :associated,
            timeout_in_secs:       1,
            wait_interval_in_secs: association_wait_interval
          )
        ).to be_nil
      end

      it 'waits for :disassociated until association clears' do
        allow(subject).to receive(:associated?).and_return(true, true, false)

        expect(
          subject.till(
            :disassociated,
            timeout_in_secs:       1,
            wait_interval_in_secs: association_wait_interval
          )
        ).to be_nil
      end

      it 'raises WaitTimeoutError for :associated when association never appears' do
        allow(subject).to receive(:associated?).and_return(false)
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1000.0, 1001.1)

        expect do
          subject.till(
            :associated,
            timeout_in_secs:       1,
            wait_interval_in_secs: association_wait_interval
          )
        end.to raise_error(WifiWand::WaitTimeoutError)
      end

      it 'raises WaitTimeoutError for :disassociated when association never clears' do
        allow(subject).to receive(:associated?).and_return(true)
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
          .and_return(1000.0, 1000.0, 1001.1)

        expect do
          subject.till(
            :disassociated,
            timeout_in_secs:       1,
            wait_interval_in_secs: association_wait_interval
          )
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
      expect(subject.wifi_on?).to be(true).or be(false)
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

      expect(subject.wifi_on?).to be(true).or be(false)
    end
  end


  # Ordinary context - model-level WiFi-on state without changing the host radio.
  context 'when wifi starts on' do
    before do
      allow(subject).to receive(:wifi_on?).and_return(true)
    end

    it_behaves_like 'interface commands complete without error'
  end

  # Ordinary context - model-level WiFi-off state without changing the host radio.
  context 'when wifi starts off' do
    before do
      allow(subject).to receive(:wifi_on?).and_return(false)
      allow(subject).to receive(:available_network_names).and_call_original
      allow(subject).to receive(:connected_network_name).and_call_original
      allow(subject).to receive(:ipv4_addresses).and_call_original
      allow(subject).to receive(:ipv6_addresses).and_call_original
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
      expect(info['ipv4_addresses']).to eq([])
      expect(info['ipv6_addresses']).to eq([])
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
        options = { wifi_interface: 'wlan1', verbose: false }
        model = subject.class.new(options)

        allow(model).to receive(:validate_os_preconditions)
        allow(model).to receive(:is_wifi_interface?).with('wlan1').and_return(true)

        model.init_wifi_interface
        expect(model.wifi_interface).to eq('wlan1')
      end
    end

    context 'when provided interface is invalid' do
      it 'raises InvalidInterfaceError' do
        options = { wifi_interface: 'invalid0', verbose: false }
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
      end
      define_base_model_required_methods(test_class, probe_wifi_interface: 'en0')

      inst = test_class.new
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

    it 'reports non-StandardError wifi info probe failures through the result queue' do
      result_queue = Queue.new
      worker = subject.send(:wifi_info_probe_worker, result_queue, :internet_tcp) do
        raise ScriptError, 'probe failed'
      end

      worker.join
      probe_name, status, payload = result_queue.pop(true)

      expect(probe_name).to eq(:internet_tcp)
      expect(status).to eq(:error)
      expect(payload).to be_a(ScriptError)
      expect(payload.message).to eq('probe failed')
    end

    it 'joins already-started wifi info probe workers when later thread creation fails' do
      started_worker = instance_double(Thread)
      allow(started_worker).to receive(:join)
      allow(subject).to receive(:wifi_info_probe_worker).and_return(started_worker)
      allow(subject).to receive(:wifi_info_probe_worker).with(anything, :dns_working).and_raise(ThreadError)

      expect do
        subject.send(:wifi_info_initial_connectivity_probe_results)
      end.to raise_error(ThreadError)
      expect(started_worker).to have_received(:join)
    end

    it 'propagates a worker that exits without publishing a probe result' do
      failed_worker = instance_double(Thread, alive?: false)
      allow(failed_worker).to receive(:value).and_raise(NoMemoryError, 'worker failed')

      expect do
        subject.send(:wifi_info_collect_probe_results, Queue.new, internet_tcp: failed_worker)
      end.to raise_error(NoMemoryError, 'worker failed')
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
        def _ipv4_addresses = []
        def _ipv6_addresses = []
        def _preferred_network_password(_network_name) = nil
      end

      expect do
        incomplete_class.verify_required_methods_implemented(incomplete_class)
      end.to raise_error(NotImplementedError, /must implement.*open_resource/)
    end

    it 'requires connection_security_type, signal_quality, and network_hidden? subclass overrides' do
      incomplete_class = Class.new(WifiWand::BaseModel) do
        def self.os_id = :test
      end
      define_base_model_required_methods(
        incomplete_class, except: %i[connection_security_type signal_quality network_hidden?]
      )

      expect do
        incomplete_class.verify_required_methods_implemented(incomplete_class)
      end.to raise_error(NotImplementedError) { |error|
        expect(error.message).to include('connection_security_type')
        expect(error.message).to include('network_hidden?')
        expect(error.message).to include('signal_quality')
      }
    end

    it 'validates anonymous subclasses during initialization' do
      incomplete_class = Class.new(WifiWand::BaseModel) do
        def self.os_id = :test
      end
      define_base_model_required_methods(
        incomplete_class, except: %i[connection_security_type signal_quality network_hidden?]
      )

      expect do
        incomplete_class.new
      end.to raise_error(NotImplementedError) { |error|
        expect(error.message).to include('Subclass (anonymous)')
        expect(error.message).to include('connection_security_type')
        expect(error.message).to include('network_hidden?')
        expect(error.message).to include('signal_quality')
      }
    end

    # NOTE: TracePoint callback testing is unreliable due to test mocking interference.
    # Instead, we test verify_required_methods_implemented directly above.

    it 'raises NotImplementedError for explicit BaseModel abstract methods' do
      base_model_instance = WifiWand::BaseModel.new

      expect do
        base_model_instance.default_interface
      end.to raise_error(NotImplementedError, /must implement default_interface/)

      expect do
        base_model_instance.connection_security_type
      end.to raise_error(NotImplementedError, /must implement connection_security_type/)
      expect do
        base_model_instance.signal_quality
      end.to raise_error(NotImplementedError, /must implement signal_quality/)
      expect do
        base_model_instance.network_hidden?
      end.to raise_error(NotImplementedError, /must implement network_hidden\?/)
    end

    it 'verifies concrete model classes implement the full required contract' do
      [WifiWand::Platforms::Mac::Model, WifiWand::Platforms::Ubuntu::Model].each do |model_class|
        expect do
          WifiWand::BaseModel.verify_required_methods_implemented(model_class)
        end.not_to raise_error
      end
    end

    it 'verifies concrete model public override methods are public subclass methods' do
      [WifiWand::Platforms::Mac::Model, WifiWand::Platforms::Ubuntu::Model].each do |model_class|
        public_methods = WifiWand::BaseModel::REQUIRED_SUBCLASS_METHODS
          .select { |_method_name, required_visibility| required_visibility == :public }
          .keys
        missing_methods = public_methods.reject do |method_name|
          model_class.public_method_defined?(method_name) &&
            model_class.public_instance_method(method_name).owner != WifiWand::BaseModel
        end

        expect(missing_methods).to eq([])
      end
    end
  end

  describe '#wifi_info exception handling' do
    before do
      allow(subject).to receive_messages(
        wifi_on?:               true,
        wifi_interface:         'wlan0',
        default_interface:      'wlan0',
        connected_network_name: 'TestNet',
        bssid:                  '00:11:22:33:44:55',
        ipv4_addresses:         ['192.168.1.100'],
        ipv6_addresses:         ['2001:db8::100'],
        mac_address:            'aa:bb:cc:dd:ee:ff',
        nameservers:            ['8.8.8.8']
      )

      allow(subject).to receive(:internet_connectivity_state).and_call_original
    end

    shared_context 'for verbose test model setup' do
      let(:captured_output) { StringIO.new }

      let(:test_model) do
        model_options = { verbose: true, wifi_interface: nil, out_stream: captured_output }
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
          bssid:                      '00:11:22:33:44:55',
          ipv4_addresses:             ['192.168.1.100'],
          ipv6_addresses:             ['2001:db8::100'],
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

      expect(result['internet_tcp_connectivity']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
      expect(result['captive_portal_login_required']).to eq(:unknown)
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

    it 'does not call captive portal checks when TCP fails' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               true
      )
      expect(subject.connectivity_tester).not_to receive(:captive_portal_login_required)

      result = subject.wifi_info
      expect(result['captive_portal_login_required']).to eq(:unknown)
    end

    it 'does not call captive portal checks when DNS fails' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               false
      )
      expect(subject.connectivity_tester).not_to receive(:captive_portal_login_required)

      result = subject.wifi_info
      expect(result['captive_portal_login_required']).to eq(:unknown)
    end

    it 'does not call captive portal checks when both TCP and DNS fail' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               false
      )
      expect(subject.connectivity_tester).not_to receive(:captive_portal_login_required)

      result = subject.wifi_info
      expect(result['captive_portal_login_required']).to eq(:unknown)
    end

    it 'checks captive portal login requirement when both TCP and DNS succeed' do
      allow(subject).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               true
      )
      expect(subject.connectivity_tester).to receive(:captive_portal_login_required).and_return(:no)

      expect(subject.wifi_info['captive_portal_login_required']).to eq(:no)
    end

    it 'propagates unexpected TCP probe failures from worker threads' do
      allow(subject).to receive(:internet_tcp_connectivity?).and_raise(RuntimeError, 'broken probe')
      allow(subject).to receive(:dns_working?).and_return(true)

      expect { subject.wifi_info }.to raise_error(RuntimeError, 'broken probe')
    end

    it 'does not hide unexpected ipv4_addresses errors' do
      allow(subject).to receive(:ipv4_addresses)
        .and_raise(WifiWand::ConfigurationError, 'broken IPv4 implementation')

      expect { subject.wifi_info }
        .to raise_error(WifiWand::ConfigurationError, /broken IPv4 implementation/)
    end

    it 'does not hide unexpected ipv6_addresses errors' do
      allow(subject).to receive(:ipv6_addresses)
        .and_raise(WifiWand::ConfigurationError, 'broken IPv6 implementation')

      expect { subject.wifi_info }
        .to raise_error(WifiWand::ConfigurationError, /broken IPv6 implementation/)
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
      allow(subject).to receive(:has_preferred_network?) do |network_name|
        %w[Network1 Network2 Network3].include?(network_name)
      end
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
      klass = Class.new(WifiWand::BaseModel) do
        def self.os_id = :test
      end

      define_base_model_required_methods(klass)
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
        runtime_model.run_command(['bash', '-lc', 'printf runtime-config-test'])
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
        runtime_model.run_command(['bash', '-lc', 'printf configured-stream-test'])
      end

      expect(explicit_output.string).to include('StatusWaiter (wifi_on): starting')
      expect(explicit_output.string).to include('Command: bash -lc printf configured-stream-test')
      expect(redirected_output.string).to eq('')
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
        run_command:                 command_result(stdout: ''),
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
          allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(double('os', id: os_id))

          expect do
            silence_output do
              subject.generate_qr_code
            end
          end.to raise_error(WifiWand::Error, /#{Regexp.escape(expected_command)}/)
        end
      end

      it 'raises error with generic message for unknown OS' do
        allow(subject).to receive(:command_available?).with('qrencode').and_return(false)
        allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(double('os', id: :unknown))

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
        ['WPA security',      'WPA',  'WPA'],
        ['WPA2 security',     'WPA2', 'WPA'],
        ['WPA3 security',     'WPA3', 'WPA'],
        ['WEP security',      'WEP',  'WEP'],
        ['unknown security with saved password', nil, 'WPA'],
      ].each do |description, input_security, expected_qr_security|
        it "generates correct QR string for #{description}" do
          allow(subject).to receive(:connection_security_type).and_return(input_security)
          expected_qr_string = "WIFI:T:#{expected_qr_security};S:TestNetwork;P:test_password;H:false;;"

          silence_output { subject.generate_qr_code }

          expect(subject).to have_received(:run_command)
            .with(satisfy do |cmd|
              cmd.first(5) == %w[qrencode -t PNG -o -] && cmd.last == expected_qr_string
            end, log_stdout: false, binary_stdout: true)
        end
      end

      it 'defaults to WPA when security type is unknown but password exists' do
        allow(subject).to receive(:connection_security_type).and_return('RSN')
        expected_qr_string = 'WIFI:T:WPA;S:TestNetwork;P:test_password;H:false;;'

        silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_command)
          .with(
            satisfy { |cmd| cmd.first(5) == %w[qrencode -t PNG -o -] && cmd.last == expected_qr_string },
            log_stdout: false, binary_stdout: true
          )
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
            connected_network_name: test_network
          )
          allow(subject).to receive(:preferred_network_password).with(test_network).and_return(test_password)

          silence_output { subject.generate_qr_code }

          expect(subject).to have_received(:run_command)
            .with(satisfy do |cmd|
              cmd.first(5) == %w[qrencode -t PNG -o -] &&
                cmd.last == expected_qr_string
            end, log_stdout: false, binary_stdout: true)
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
        allow(subject).to receive(:connection_security_type).and_return('NONE')
        expect(subject).not_to receive(:preferred_network_password)
        expected_qr_string = 'WIFI:T:nopass;S:TestNetwork;P:;H:false;;'

        result = silence_output { subject.generate_qr_code }

        expect(subject).to have_received(:run_command)
          .with(
            satisfy { |cmd| cmd.first(5) == %w[qrencode -t PNG -o -] && cmd.last == expected_qr_string },
            log_stdout: false, binary_stdout: true
          )
        expect(result).to eq('TestNetwork-qr-code.png')
      end
    end

    context 'when printing QR codes' do
      it 'renders ANSI QR to a string without printing' do
        out_stream = StringIO.new
        subject.out_stream = out_stream
        allow(subject).to receive(:run_command)
          .with(
            satisfy { |cmd| cmd.first(5) == %w[qrencode -t ANSI -o -] },
            log_stdout: false, binary_stdout: false
          )
          .and_return(command_result(stdout: "[QR-ANSI]\n"))

        result = subject.render_qr_code(format: :ansi)

        expect(result).to eq("[QR-ANSI]\n")
        expect(out_stream.string).to eq('')
      end

      it 'prints ANSI QR to the model output stream and returns nil' do
        out_stream = StringIO.new
        subject.out_stream = out_stream
        allow(subject).to receive(:run_command)
          .with(
            satisfy { |cmd| cmd.first(5) == %w[qrencode -t ANSI -o -] },
            log_stdout: false, binary_stdout: false
          )
          .and_return(command_result(stdout: "[QR-ANSI]\n"))

        result = subject.print_qr_code

        expect(result).to be_nil
        expect(out_stream.string).to include('[QR-ANSI]')
      end
    end

    context 'when handling errors' do
      it 'raises WifiWand::Error when qrencode command fails' do
        allow(subject).to receive(:run_command)
          .and_raise(os_command_error(exitstatus: 1, command: 'qrencode', text: 'Command failed'))

        expect { silence_output { subject.generate_qr_code } }
          .to raise_error(WifiWand::Error, /Failed to generate QR code/)
      end
    end
  end
end
