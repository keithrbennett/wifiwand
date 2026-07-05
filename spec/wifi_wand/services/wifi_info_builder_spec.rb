# frozen_string_literal: true

require_relative '../../spec_helper'

describe WifiWand::WifiInfoBuilder do
  subject(:builder) { described_class.new(mock_model, runtime_config: runtime_config) }

  let(:mock_model) { build_mock_model }
  let(:runtime_config) { WifiWand::RuntimeConfig.new(verbose: false, out_stream: StringIO.new, err_stream: StringIO.new) }


  def build_mock_model(overrides = {})
    defaults = {
      wifi_on?:                      true,
      wifi_interface:                'wlan0',
      default_interface:             'wlan0',
      connected_network_name:        'TestNetwork',
      bssid:                         '00:11:22:33:44:55',
      signal_quality:                WifiWand::SignalQuality.new(value: 72, unit: :percent),
      ipv4_addresses:                ['192.168.1.100'],
      ipv6_addresses:                ['2001:db8::100'],
      mac_address:                   'aa:bb:cc:dd:ee:ff',
      nameservers:                   ['8.8.8.8', '8.8.4.4'],
      connected?:                    true,
      internet_tcp_connectivity?:    true,
      dns_working?:                  true,
      captive_portal_login_required: :no,
    }
    double('model', defaults.merge(overrides))
  end

  describe '#build' do
    it 'returns hash with consistent structure' do
      result = builder.build
      expect(result).to be_a(Hash)

      expect(result).to include(
        'wifi_on', 'internet_tcp_connectivity', 'dns_working', 'captive_portal_login_required',
        'internet_connectivity_state', 'interface', 'default_interface', 'connected', 'network',
        'bssid', 'signal_quality', 'ssid_identity_available', 'ssid_identity_status', 'ssid_identity_warning',
        'ipv4_addresses', 'ipv6_addresses', 'mac_address', 'nameservers', 'timestamp'
      )

      expect(result['wifi_on']).to be(true).or be(false)
      expect(result['connected']).to(satisfy { |value| [true, false, nil].include?(value) })
      expect(result['signal_quality']).to eq(value: 72, unit: :percent)
      expect(result['ssid_identity_available']).to be(true).or be(false)
      expect(result['ssid_identity_status']).to(satisfy do |value|
        %w[available unavailable not_connected unknown].include?(value)
      end)
      expect(result['internet_tcp_connectivity']).to be(true).or be(false)
      expect(result['dns_working']).to be(true).or be(false)
      expect(result['captive_portal_login_required']).to(satisfy do |value|
        %i[yes no unknown].include?(value)
      end)
      expect(result['internet_connectivity_state']).to(satisfy do |value|
        %i[reachable unreachable indeterminate].include?(value)
      end)
      expect(result['timestamp']).to be_a(Time)
    end

    it 'does not include preferred or available network lists' do
      result = builder.build

      expect(result).not_to have_key('preferred_networks')
      expect(result).not_to have_key('available_networks')
    end

    it 'returns nil when default_interface lookup fails' do
      allow(mock_model).to receive(:default_interface).and_raise(WifiWand::Error, 'default route unavailable')

      result = builder.build

      expect(result).to be_a(Hash)
      expect(result['default_interface']).to be_nil
    end

    it 'returns nil when mac_address lookup fails' do
      allow(mock_model).to receive(:mac_address).and_raise(WifiWand::Error, 'mac lookup unavailable')

      result = builder.build

      expect(result).to be_a(Hash)
      expect(result['mac_address']).to be_nil
    end

    it 'returns empty array when nameservers lookup fails' do
      allow(mock_model).to receive(:nameservers).and_raise(WifiWand::Error, 'dns config unavailable')

      result = builder.build

      expect(result).to be_a(Hash)
      expect(result['nameservers']).to eq([])
    end

    it 'does not include public IP data' do
      result = builder.build
      expect(result).not_to have_key('public_ip')
    end

    it 'starts TCP and DNS connectivity probes before waiting for either result' do
      dns_started_mutex = Mutex.new
      dns_started_condition = ConditionVariable.new
      dns_started = false

      allow(mock_model).to receive(:internet_tcp_connectivity?) do
        dns_started_mutex.synchronize do
          dns_started_condition.wait(dns_started_mutex, 5) unless dns_started
          raise 'DNS probe did not start while TCP probe was still running' unless dns_started
        end
        true
      end
      allow(mock_model).to receive(:dns_working?) do
        dns_started_mutex.synchronize do
          dns_started = true
          dns_started_condition.broadcast
        end
        true
      end

      expect(builder.build['internet_connectivity_state']).to eq(:reachable)
    end
  end

  describe 'exception handling' do
    it 'handles internet_tcp_connectivity exceptions' do
      allow(mock_model).to receive(:internet_tcp_connectivity?).and_raise(SocketError, 'Network error')
      allow(mock_model).to receive(:dns_working?).and_return(true)

      result = builder.build

      expect(result['internet_tcp_connectivity']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
      expect(result['captive_portal_login_required']).to eq(:unknown)
    end

    it 'handles dns_working exceptions' do
      allow(mock_model).to receive(:dns_working?).and_raise(SocketError, 'DNS error')
      allow(mock_model).to receive(:internet_tcp_connectivity?).and_return(true)

      result = builder.build
      expect(result['dns_working']).to be false
      expect(result['internet_connectivity_state']).to eq(:unreachable)
    end

    it 'does not call captive portal checks when TCP fails' do
      allow(mock_model).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               true
      )

      result = builder.build
      expect(result['captive_portal_login_required']).to eq(:unknown)
      expect(mock_model).not_to have_received(:captive_portal_login_required)
    end

    it 'does not call captive portal checks when DNS fails' do
      allow(mock_model).to receive_messages(
        internet_tcp_connectivity?: true,
        dns_working?:               false
      )

      result = builder.build
      expect(result['captive_portal_login_required']).to eq(:unknown)
      expect(mock_model).not_to have_received(:captive_portal_login_required)
    end

    it 'does not call captive portal checks when both TCP and DNS fail' do
      allow(mock_model).to receive_messages(
        internet_tcp_connectivity?: false,
        dns_working?:               false
      )

      result = builder.build
      expect(result['captive_portal_login_required']).to eq(:unknown)
      expect(mock_model).not_to have_received(:captive_portal_login_required)
    end

    it 'checks captive portal login requirement when both TCP and DNS succeed' do
      allow(mock_model).to receive_messages(
        internet_tcp_connectivity?:    true,
        dns_working?:                  true,
        captive_portal_login_required: :no
      )

      expect(builder.build['captive_portal_login_required']).to eq(:no)
      expect(mock_model).to have_received(:captive_portal_login_required)
    end

    it 'propagates unexpected TCP probe failures from worker threads' do
      allow(mock_model).to receive(:internet_tcp_connectivity?).and_raise(RuntimeError, 'broken probe')
      allow(mock_model).to receive(:dns_working?).and_return(true)

      expect { builder.build }.to raise_error(RuntimeError, 'broken probe')
    end

    it 'does not hide unexpected ipv4_addresses errors' do
      allow(mock_model).to receive(:ipv4_addresses)
        .and_raise(WifiWand::ConfigurationError, 'broken IPv4 implementation')

      expect { builder.build }
        .to raise_error(WifiWand::ConfigurationError, /broken IPv4 implementation/)
    end

    it 'does not hide unexpected ipv6_addresses errors' do
      allow(mock_model).to receive(:ipv6_addresses)
        .and_raise(WifiWand::ConfigurationError, 'broken IPv6 implementation')

      expect { builder.build }
        .to raise_error(WifiWand::ConfigurationError, /broken IPv6 implementation/)
    end
  end

  describe '#successful_available_network_scan' do
    it 'wraps networks in the expected result hash' do
      result = builder.successful_available_network_scan(%w[Net1 Net2])

      expect(result).to eq(
        'networks'          => %w[Net1 Net2],
        'scan_status'       => 'ok',
        'scan_source'       => 'os',
        'ssid_data_trusted' => true,
        'warning'           => nil
      )
    end

    it 'coerces a nil argument to an empty array' do
      result = builder.successful_available_network_scan(nil)

      expect(result['networks']).to eq([])
    end
  end

  describe 'private helpers' do
    it 'reports non-StandardError wifi info probe failures through the result queue' do
      result_queue = Queue.new
      worker = builder.send(:wifi_info_probe_worker, result_queue, :internet_tcp) do
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
      allow(builder).to receive(:wifi_info_probe_worker).and_return(started_worker)
      allow(builder).to receive(:wifi_info_probe_worker)
        .with(anything, :dns_working).and_raise(ThreadError)

      expect do
        builder.send(:wifi_info_initial_connectivity_probe_results)
      end.to raise_error(ThreadError)
      expect(started_worker).to have_received(:join)
    end

    it 'propagates a worker that exits without publishing a probe result' do
      failed_worker = instance_double(Thread, alive?: false)
      allow(failed_worker).to receive(:value).and_raise(NoMemoryError, 'worker failed')

      expect do
        builder.send(:wifi_info_collect_probe_results, Queue.new, internet_tcp: failed_worker)
      end.to raise_error(NoMemoryError, 'worker failed')
    end
  end
end
