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

  describe '#nameservers_using_resolv_conf' do
    let(:model) { described_class.new(model_options) }

    it 'returns nil when resolv.conf is unavailable' do
      allow(File).to receive(:readlines).with('/etc/resolv.conf').and_raise(Errno::ENOENT)

      expect(model.nameservers_using_resolv_conf).to be_nil
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
      allow(described_class).to receive(:verify_required_methods_implemented).and_call_original

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

      expect(described_class).to have_received(:verify_required_methods_implemented).with(subclass)
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
    let(:output) { StringIO.new }
    let(:tester) do
      double('tester', internet_connectivity_state: :reachable, tcp_connectivity?: true, dns_working?: true)
    end

    before do
      model.instance_variable_set(:@runtime_config, WifiWand::RuntimeConfig.new(
        verbose:    true,
        out_stream: output
      ))
      model.instance_variable_set(:@connectivity_tester, tester)
    end

    it 'logs and delegates internet_tcp_connectivity?' do
      expect(model.internet_tcp_connectivity?).to be true
      expect(output.string).to include('Entered BaseModel#internet_tcp_connectivity?')
    end

    it 'logs and delegates dns_working?' do
      expect(model.dns_working?).to be true
      expect(output.string).to include('Entered BaseModel#dns_working?')
    end
  end

  describe '#debug_method_entry' do
    let(:output) { StringIO.new }
    let(:model) { described_class.new(verbose: true, out_stream: output) }

    it 'omits parameter parentheses when no parameters are requested' do
      model.send(:debug_method_entry, :probe_wifi_interface)

      expect(output.string).to eq("Entered BaseModel#probe_wifi_interface\n")
    end

    it 'includes parameter values when parameters are requested' do
      network_name = 'CafeNet'
      password = 'secret'

      model.send(:debug_method_entry, :connect, binding, %i[network_name password])

      expect(output.string).to eq("Entered BaseModel#connect(\"CafeNet\", \"secret\")\n")
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

  describe 'public IP lookups' do
    let(:model) { described_class.new(model_options) }
    let(:fake_http) { double('http') }

    before do
      allow(fake_http).to receive(:use_ssl=)
      allow(fake_http).to receive(:open_timeout=)
      allow(fake_http).to receive(:read_timeout=)
      allow(fake_http).to receive(:respond_to?).with(:write_timeout=).and_return(false)
      allow(Net::HTTP).to receive(:new).and_return(fake_http)
    end

    it 'parses successful info responses' do
      fake_response = double('response', body: '{"ip":"203.0.113.5","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(model.public_ip_info).to eq('address' => '203.0.113.5', 'country' => 'TH')
    end

    it 'parses successful IPv6 info responses' do
      fake_response = double('response', body: '{"ip":"2001:db8::1","country":"TH"}')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(model.public_ip_info).to eq('address' => '2001:db8::1', 'country' => 'TH')
    end

    it 'parses successful address responses' do
      fake_response = double('response', body: '203.0.113.5')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect(model.public_ip_address).to eq('203.0.113.5')
    end

    it 'raises timeout errors clearly' do
      allow(model).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(Net::ReadTimeout)

      expect { model.public_ip_address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: timeout')
    end

    it 'retries transient timeout errors before returning a successful address' do
      allow(model).to receive(:sleep)
      fake_response = double('response', body: '203.0.113.5')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      request_count = 0
      allow(fake_http).to receive(:request) do
        request_count += 1
        raise Net::ReadTimeout if request_count < 3

        fake_response
      end

      expect(model.public_ip_address).to eq('203.0.113.5')
      expect(model).to have_received(:sleep).with(0.2)
      expect(model).to have_received(:sleep).with(0.4)
    end

    it 'stops after the configured retry budget is exhausted' do
      allow(model).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { model.public_ip_address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: network error')
      expect(fake_http).to have_received(:request).exactly(3).times
    end

    it 'does not retry non-rate-limited client errors' do
      fake_response = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(fake_http).to receive(:request).and_return(fake_response)
      allow(model).to receive(:sleep)

      expect { model.public_ip_address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: HTTP 400 Bad Request')
      expect(fake_http).to have_received(:request).once
      expect(model).not_to have_received(:sleep)
    end

    it 'preserves the request URL on transport errors' do
      allow(model).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { model.public_ip_address }.to raise_error(WifiWand::PublicIPLookupError) { |error|
        expect(error.message).to eq('Public IP lookup failed: network error')
        expect(error.url).to eq('https://api.ipify.org')
      }
    end

    it 'raises transport errors clearly' do
      allow(model).to receive(:sleep)
      allow(fake_http).to receive(:request).and_raise(SocketError, 'lookup failed')

      expect { model.public_ip_address }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: network error')
    end

    it 'stores malformed response details on the error in verbose mode' do
      output = StringIO.new
      fake_response = double('response', body: '{"ip":"not-an-ip","country":"TH"}')
      model.instance_variable_set(:@runtime_config, WifiWand::RuntimeConfig.new(
        verbose:    true,
        out_stream: output
      ))
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:request).and_return(fake_response)

      expect { model.public_ip_info }.to raise_error(WifiWand::PublicIPLookupError) { |error|
        expect(error.message).to eq('Public IP lookup failed: malformed response')
        expect(error.url).to eq('https://api.country.is/')
        expect(error.body).to eq('{"ip":"not-an-ip","country":"TH"}')
      }
      expect(output.string).to eq('')
    end

    it 'raises rate limit errors clearly' do
      fake_response = instance_double(Net::HTTPResponse, code: '429', message: 'Too Many Requests')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(fake_http).to receive(:request).and_return(fake_response)
      allow(model).to receive(:sleep)

      expect { model.public_ip_info }
        .to raise_error(WifiWand::PublicIPLookupError, 'Public IP lookup failed: rate limited') { |error|
          expect(error.status_code).to eq('429')
        }
      expect(fake_http).to have_received(:request).once
      expect(model).not_to have_received(:sleep)
    end
  end

  describe 'helper memoization' do
    let(:model) { described_class.new(model_options) }

    it 'memoizes qr_code_generator helper' do
      helper = double('qr')
      allow(WifiWand::Helpers::QrCodeGenerator).to receive(:new).and_return(helper)

      first = model.send(:qr_code_generator)
      second = model.send(:qr_code_generator)

      expect(first).to equal(helper)
      expect(second).to equal(helper)
    end

    it 'logs and delegates capture_network_state' do
      output = StringIO.new
      manager = double('state_manager')

      model.instance_variable_set(:@runtime_config, WifiWand::RuntimeConfig.new(
        verbose:    true,
        out_stream: output
      ))
      model.instance_variable_set(:@state_manager, manager)

      expect(manager).to receive(:capture_network_state).and_return(:snapshot)

      expect(model.capture_network_state).to eq(:snapshot)
      expect(output.string).to include('Entered BaseModel#capture_network_state')
    end
  end
end
