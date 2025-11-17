# frozen_string_literal: true

require_relative '../../spec_helper'
require 'ostruct'
require 'stringio'

RSpec.describe WifiWand::BaseModel do
  describe '#ensure_wifi_interface!' do
    let(:model) { described_class.allocate }

    it 'returns existing interface without reinitializing' do
      model.instance_variable_set(:@wifi_interface, 'wlan0')

      expect(model).not_to receive(:init_wifi_interface)
      expect(model.send(:ensure_wifi_interface!)).to eq('wlan0')
    end

    it 'initializes lazily when interface missing' do
      allow(model).to receive(:init_wifi_interface) do
        model.instance_variable_set(:@wifi_interface, 'wlan0')
      end

      expect(model.send(:ensure_wifi_interface!)).to eq('wlan0')
    end

    it 'propagates errors when initialization fails' do
      allow(model).to receive(:init_wifi_interface).and_raise('boom')

      expect { model.send(:ensure_wifi_interface!) }.to raise_error('boom')
    end
  end

  describe '#nameservers_using_resolv_conf' do
    let(:model) { described_class.allocate }

    it 'returns nil when resolv.conf is unavailable' do
      allow(File).to receive(:readlines).with('/etc/resolv.conf').and_raise(Errno::ENOENT)

      expect(model.nameservers_using_resolv_conf).to be_nil
    end
  end

  describe '.inherited' do
    it 'verifies underscore-prefixed methods after subclass definition' do
      allow(described_class).to receive(:verify_underscore_methods_implemented).and_call_original

      klass_name = :TracePointSpecModel
      Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)

      begin
        Object.class_eval <<-RUBY, __FILE__, __LINE__ + 1
          class TracePointSpecModel < WifiWand::BaseModel
            def self.os_id
              :trace_test
            end

            def validate_os_preconditions; end
            def detect_wifi_interface; 'wlan0'; end
            def connection_security_type; nil; end
            def is_wifi_interface?(_iface); true; end
            def mac_address; '00:00:00:00:00:00'; end
            def nameservers; []; end
            def open_application(_app); end
            def open_resource(_resource); end
            def preferred_networks; []; end
            def remove_preferred_network(_name); end
            def set_nameservers(_servers); end
            def wifi_off; end
            def wifi_on; end
            def wifi_on?; false; end

            def _available_network_names; []; end
            def _connected_network_name; nil; end
            def _connect(_network, _password); end
            def _disconnect; end
            def _ip_address; nil; end
            def _preferred_network_password(_network); nil; end
          end
        RUBY

        subclass = Object.const_get(klass_name)
        expect(described_class).to have_received(:verify_underscore_methods_implemented).with(subclass)
      ensure
        Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
      end
    end
  end

  describe 'WiFi-off wrappers' do
    let(:model) { described_class.allocate }

    before do
      allow(model).to receive(:wifi_on?).and_return(false)
    end

    it 'returns nil from connected_network_name without calling implementation' do
      expect(model).not_to receive(:_connected_network_name)
      expect(model.connected_network_name).to be_nil
    end

    it 'returns nil from ip_address without calling implementation' do
      expect(model).not_to receive(:_ip_address)
      expect(model.ip_address).to be_nil
    end
  end

  describe 'debug-logged connectivity checks' do
    let(:model) { described_class.allocate }
    let(:output) { StringIO.new }
    let(:tester) do
      double('tester', connected_to_internet?: true, tcp_connectivity?: true, dns_working?: true)
    end

    before do
      model.instance_variable_set(:@verbose_mode, true)
      model.instance_variable_set(:@original_out_stream, output)
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

  describe '#preferred_network_password' do
    let(:model) { described_class.allocate }

    it 'returns stored password when network exists' do
      allow(model).to receive(:preferred_networks).and_return(['CafeNet'])
      allow(model).to receive(:_preferred_network_password).with('CafeNet').and_return('secret')

      expect(model.preferred_network_password('CafeNet')).to eq('secret')
    end

    it 'raises when network is missing' do
      allow(model).to receive(:preferred_networks).and_return([])

      expect { model.preferred_network_password('Unknown') }
        .to raise_error(WifiWand::PreferredNetworkNotFoundError)
    end
  end

  describe '#public_ip_address_info' do
    let(:model) { described_class.allocate }

    it 'parses successful responses' do
      fake_http = double('http')
      fake_response = double('response', body: '{"ip":"203.0.113.5"}')

      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(fake_http).to receive(:use_ssl=)
      allow(fake_http).to receive(:open_timeout=)
      allow(fake_http).to receive(:read_timeout=)
      allow(fake_http).to receive(:respond_to?).with(:write_timeout=).and_return(false)
      allow(fake_http).to receive(:request).and_return(fake_response)
      allow(Net::HTTP).to receive(:new).and_return(fake_http)

      expect(model.public_ip_address_info).to eq('ip' => '203.0.113.5')
    end
  end

  describe 'helper memoization' do
    let(:model) { described_class.allocate }

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

      model.instance_variable_set(:@verbose_mode, true)
      model.instance_variable_set(:@original_out_stream, output)
      model.instance_variable_set(:@state_manager, manager)

      expect(manager).to receive(:capture_network_state).and_return(:snapshot)

      expect(model.capture_network_state).to eq(:snapshot)
      expect(output.string).to include('Entered BaseModel#capture_network_state')
    end
  end
end
