# frozen_string_literal: true

require 'spec_helper'
require 'wifi-wand/client'
require 'wifi-wand/errors'
require 'ostruct'

RSpec.describe WifiWand::Client do
  let(:mock_model) { instance_double('WifiWand::MacOsModel') }
  let(:options) { OpenStruct.new }

  before do
    allow(WifiWand::OperatingSystems).to receive(:create_model_for_current_os).and_return(mock_model)
  end

  describe '#verbose_mode' do
    let(:client) { described_class.new(options) }

    it 'reads the verbose mode from the model when called without args' do
      allow(mock_model).to receive(:verbose_mode).and_return(true)
      expect(client.verbose_mode).to be(true)
      expect(mock_model).to have_received(:verbose_mode)
    end

    it 'sets the verbose mode on the model when passed a boolean' do
      expect(mock_model).to receive(:verbose_mode=).with(true).and_return(true)
      client.verbose_mode(true)

      allow(mock_model).to receive(:verbose_mode).and_return(true)
      expect(client.verbose_mode).to be(true)
    end

    it 'coerces non-boolean values to boolean when setting' do
      expect(mock_model).to receive(:verbose_mode=).with(false)
      client.verbose_mode(nil)

      expect(mock_model).to receive(:verbose_mode=).with(true)
      client.verbose_mode('yes')
    end
  end

  describe '#initialize' do
    it 'creates a model instance for the current OS' do
      client = described_class.new(options)
      expect(client.model).to eq(mock_model)
      expect(WifiWand::OperatingSystems).to have_received(:create_model_for_current_os).with(options)
    end

    it 're-raises NoSupportedOSError if no OS is detected' do
      allow(WifiWand::OperatingSystems).to receive(:create_model_for_current_os).and_raise(WifiWand::NoSupportedOSError)
      expect { described_class.new }.to raise_error(WifiWand::NoSupportedOSError)
    end
  end

  describe '#connect' do
    let(:client) { described_class.new(options) }
    let(:network_name) { 'TestNetwork' }
    let(:password) { 'password123' }

    it 'delegates the connect call to the model' do
      allow(mock_model).to receive(:connect)
      client.connect(network_name, password)
      expect(mock_model).to have_received(:connect).with(network_name, password)
    end

    it 'handles connections without a password' do
      allow(mock_model).to receive(:connect)
      client.connect(network_name)
      expect(mock_model).to have_received(:connect).with(network_name)
    end

    it 'propagates errors from the model' do
      allow(mock_model).to receive(:connect).and_raise(WifiWand::NetworkConnectionError.new(network_name))
      expect { client.connect(network_name, password) }.to raise_error(WifiWand::NetworkConnectionError)
    end
  end

  describe 'method delegation' do
    let(:client) { described_class.new(options) }

    # Test simple, no-argument delegations in a loop by referencing the authoritative list
    # from the Client class itself, excluding methods that require arguments.
    methods_with_args = [:connect, :connected_to?, :remove_preferred_networks, :generate_qr_code]
    delegated_methods_without_args = WifiWand::Client::DELEGATED_METHODS - methods_with_args

    delegated_methods_without_args.each do |method_name|
      it "delegates ##{method_name} to the model" do
        return_value = "test_value_for_#{method_name}"
        allow(mock_model).to receive(method_name).and_return(return_value)
        result = client.public_send(method_name)
        expect(mock_model).to have_received(method_name)
        expect(result).to eq(return_value)
      end
    end

    # Test methods with arguments separately to ensure correct argument passing
    it 'delegates #connected_to? to the model' do
      allow(mock_model).to receive(:connected_to?).with('some_network').and_return(true)
      expect(client.connected_to?('some_network')).to be(true)
    end

    it 'delegates #remove_preferred_networks to the model' do
      allow(mock_model).to receive(:remove_preferred_networks).with('net1', 'net2')
      client.remove_preferred_networks('net1', 'net2')
      expect(mock_model).to have_received(:remove_preferred_networks).with('net1', 'net2')
    end

    it 'delegates #generate_qr_code to the model' do
      allow(mock_model).to receive(:generate_qr_code).with('test.png').and_return('test.png')
      expect(client.generate_qr_code('test.png')).to eq('test.png')
    end

  end
end
