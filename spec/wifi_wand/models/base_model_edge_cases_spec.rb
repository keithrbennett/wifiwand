# frozen_string_literal: true

require_relative '../../spec_helper'
require 'stringio'

RSpec.describe WifiWand::BaseModel do
  let(:model_options) { { verbose: false, out_stream: StringIO.new } }

  describe '#wifi_interface' do
    let(:model) { described_class.new(model_options) }

    it 'returns existing interface without reinitializing' do
      model.instance_variable_set(:@wifi_interface, 'wlan0')

      expect(model).not_to receive(:init_wifi_interface)
      expect(model.wifi_interface).to eq('wlan0')
    end

    it 'initializes lazily when interface missing' do
      allow(model).to receive(:init_wifi_interface) do
        model.instance_variable_set(:@wifi_interface, 'wlan0')
      end

      expect(model.wifi_interface).to eq('wlan0')
    end

    it 'propagates errors when initialization fails' do
      allow(model).to receive(:init_wifi_interface).and_raise('boom')

      expect { model.wifi_interface }.to raise_error('boom')
    end
  end

  describe '#status_network_identity' do
    let(:model) { described_class.new(model_options) }

    it 'raises for bounded status lookup when a subclass has not implemented it' do
      expect { model.status_network_identity(timeout_in_secs: 0.5) }
        .to raise_error(WifiWand::MethodNotImplementedError)
    end
  end

  describe '.inherited' do
    # BaseModel waits until the subclass body has finished before checking
    # required methods. This protects subclasses from being validated while
    # their method definitions are still in progress.
    it 'verifies required subclass methods after subclass definition' do
      contract = WifiWand::ModelSubclassContract
      allow(contract).to receive(:verify_required_methods_implemented).and_call_original

      # BaseModel verifies subclass implementations from a TracePoint(:end)
      # callback. Class.new(described_class) does not emit the class-body :end
      # event this production path depends on, so this example must define a
      # real class body.
      #
      # The class still lives inside an anonymous namespace rather than Object.
      # That gives the class a constant name for the TracePoint path without
      # leaking a global test constant or needing remove_const cleanup.
      namespace = Module.new
      namespace.module_eval <<-RUBY, __FILE__, __LINE__ + 1
        class TracePointSpecModel < WifiWand::BaseModel
          def self.os_id
            :trace_test
          end

          def bssid = '00:11:22:33:44:55'
          def signal_quality = nil
          def connected? = false
          def validate_os_preconditions = nil
          def probe_wifi_interface = 'wlan0'
          def connection_security_type = nil
          def default_interface = 'wlan0'
          def is_wifi_interface?(_iface) = true
          def mac_address = '00:00:00:00:00:00'
          def nameservers = []
          def network_hidden? = false
          def open_resource(_resource) = nil
          def preferred_networks = []
          def remove_preferred_network(_name) = nil
          def set_nameservers(_servers) = nil
          def wifi_off = nil
          def wifi_on = nil
          def wifi_on? = false

          def _available_network_names = []
          def _connected_network_name = nil
          def _connect(_network, _password) = nil
          def _disconnect = nil
          def _ipv4_addresses = []
          def _ipv6_addresses = []
          def _preferred_network_password(_network) = nil
        end
      RUBY

      subclass = namespace.const_get(:TracePointSpecModel)

      expect(contract).to have_received(:verify_required_methods_implemented).with(subclass)
    end
  end

  describe 'WiFi-off wrappers' do
    let(:model) { described_class.new(model_options) }

    before do
      allow(model).to receive_messages(wifi_on?: false, connected?: false)
    end

    it 'raises Error from connected_network_name without calling implementation' do
      expect(model).not_to receive(:_connected_network_name)
      expect { model.connected_network_name }.to raise_error(WifiWand::Error, /WiFi is off/)
    end

    it 'raises Error from available_network_names without calling implementation' do
      expect(model).not_to receive(:_available_network_names)
      expect { model.available_network_names }.to raise_error(WifiWand::Error, /WiFi is off/)
    end

    it 'raises Error from ipv4_addresses without calling implementation' do
      expect(model).not_to receive(:_ipv4_addresses)
      expect { model.ipv4_addresses }.to raise_error(WifiWand::Error, /not connected/)
    end

    it 'raises Error from ipv6_addresses without calling implementation' do
      expect(model).not_to receive(:_ipv6_addresses)
      expect { model.ipv6_addresses }.to raise_error(WifiWand::Error, /not connected/)
    end

    it 'raises Error from connected_network_password without calling implementation' do
      expect(model).not_to receive(:_connected_network_name)
      expect(model).not_to receive(:preferred_network_password)
      expect { model.send(:connected_network_password) }.to raise_error(WifiWand::Error, /WiFi is off/)
    end
  end

  describe 'wifi on, not connected' do
    let(:model) { described_class.new(model_options) }

    before do
      allow(model).to receive_messages(wifi_on?: true, connected?: false, _connected_network_name: nil)
    end

    it 'connected_network_name returns nil' do
      expect(model.connected_network_name).to be_nil
    end

    it 'connected_network_password returns nil' do
      expect(model.send(:connected_network_password)).to be_nil
    end

    it 'ipv4_addresses raises Error' do
      expect(model).not_to receive(:_ipv4_addresses)
      expect { model.ipv4_addresses }.to raise_error(WifiWand::Error, /not connected/)
    end

    it 'ipv6_addresses raises Error' do
      expect(model).not_to receive(:_ipv6_addresses)
      expect { model.ipv6_addresses }.to raise_error(WifiWand::Error, /not connected/)
    end
  end

  describe 'debug-logged connectivity checks' do
    let(:model) { described_class.new(model_options) }
    let(:err_output) { StringIO.new }
    let(:tester) do
      double('tester', internet_connectivity_state: :reachable, tcp_connectivity?: true, dns_working?: true)
    end

    before do
      model.instance_variable_set(:@runtime_config, WifiWand::RuntimeConfig.new(
        verbose:    true,
        err_stream: err_output
      ))
      model.instance_variable_set(:@connectivity_tester, tester)
    end

    it 'logs and delegates internet_tcp_connectivity?' do
      expect(model.internet_tcp_connectivity?).to be true
      expect(err_output.string).to include('Entered BaseModel#internet_tcp_connectivity?')
    end

    it 'logs and delegates dns_working?' do
      expect(model.dns_working?).to be true
      expect(err_output.string).to include('Entered BaseModel#dns_working?')
    end
  end

  describe '#debug_method_entry' do
    let(:err_output) { StringIO.new }
    let(:model) { described_class.new(verbose: true, err_stream: err_output) }

    it 'omits parameter parentheses when no parameters are requested' do
      model.send(:debug_method_entry, :probe_wifi_interface)

      expect(err_output.string).to eq("Entered BaseModel#probe_wifi_interface\n")
    end

    it 'includes parameter values when parameters are requested' do
      network_name = 'CafeNet'
      password = 'secret'

      model.send(:debug_method_entry, :connect, binding, %i[network_name password])

      expect(err_output.string).to eq("Entered BaseModel#connect(\"CafeNet\", \"secret\")\n")
    end
  end

  describe '#status_line_data' do
    let(:model) { described_class.new(model_options) }

    it 'does not invoke deprecated connectivity shortcuts directly' do
      allow(WifiWand::StatusLineDataBuilder).to receive(:call).and_return({ wifi_on: true })

      expect(model).not_to receive(:internet_connectivity_state)

      expect(model.status_line_data).to eq(wifi_on: true)
    end
  end

  describe '#preferred_network_password' do
    let(:model) { described_class.new(model_options) }

    it 'returns the stored password using the resolved lookup name' do
      allow(model).to receive(:preferred_networks).and_return(['CafeNet'])
      expect(model).to receive(:_preferred_network_password).with('CafeNet').and_return('secret')

      expect(model.preferred_network_password('CafeNet')).to eq('secret')
    end

    it 'forwards an explicit timeout override to the subclass implementation' do
      allow(model).to receive(:preferred_networks).and_return(['CafeNet'])
      expect(model).to receive(:_preferred_network_password)
        .with('CafeNet', timeout_in_secs: nil)
        .and_return('secret')

      expect(model.preferred_network_password('CafeNet', timeout_in_secs: nil)).to eq('secret')
    end

    it 'raises when network is missing' do
      allow(model).to receive(:preferred_networks).and_return([])

      expect { model.preferred_network_password('Unknown') }
        .to raise_error(WifiWand::PreferredNetworkNotFoundError)
    end
  end

  describe 'public IP lookup delegation' do
    let(:model) { described_class.new(model_options) }

    it 'memoizes the public_ip_lookup service' do
      first = model.public_ip_lookup
      second = model.public_ip_lookup
      expect(first).to be_a(WifiWand::PublicIpLookup)
      expect(second).to equal(first)
    end

    it 'delegates public_ip_info to the lookup service' do
      stub = instance_double(WifiWand::PublicIpLookup, info: { 'address' => '1.2.3.4', 'country' => 'US' })
      model.instance_variable_set(:@public_ip_lookup, stub)

      expect(model.public_ip_info).to eq('address' => '1.2.3.4', 'country' => 'US')
    end

    it 'delegates public_ip_address to the lookup service' do
      stub = instance_double(WifiWand::PublicIpLookup, address: '1.2.3.4')
      model.instance_variable_set(:@public_ip_lookup, stub)

      expect(model.public_ip_address).to eq('1.2.3.4')
    end

    it 'delegates public_ip_country to the lookup service' do
      stub = instance_double(WifiWand::PublicIpLookup, country: 'US')
      model.instance_variable_set(:@public_ip_lookup, stub)

      expect(model.public_ip_country).to eq('US')
    end
  end

  describe 'helper memoization' do
    let(:model) { described_class.new(model_options) }

    it 'memoizes qr_code_generator helper' do
      helper = double('qr')
      allow(WifiWand::Models::Helpers::QrCodeGenerator).to receive(:new).and_return(helper)

      first = model.send(:qr_code_generator)
      second = model.send(:qr_code_generator)

      expect(first).to equal(helper)
      expect(second).to equal(helper)
    end

    it 'logs and delegates capture_network_state' do
      err_output = StringIO.new
      manager = double('state_manager')

      model.instance_variable_set(:@runtime_config, WifiWand::RuntimeConfig.new(
        verbose:    true,
        err_stream: err_output
      ))
      model.instance_variable_set(:@state_manager, manager)

      expect(manager).to receive(:capture_network_state).and_return(:snapshot)

      expect(model.capture_network_state).to eq(:snapshot)
      expect(err_output.string).to include('Entered BaseModel#capture_network_state')
    end
  end
end
