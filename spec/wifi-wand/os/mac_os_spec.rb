# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/os/mac_os'

describe WifiWand::MacOs do
  subject(:os) { described_class.new }

  describe '#initialize' do
    it 'sets correct id and display_name' do
      expect(os.id).to eq(:mac)
      expect(os.display_name).to eq('macOS')
    end
  end

  describe '#current_os_is_this_os?' do
    detection_scenarios = [
      ['detects macOS with darwin host_os',                   'darwin',          true],
      ['detects macOS with darwin-based host_os',             'x86_64-darwin21', true],
      ['returns false for Linux system',                      'linux-gnu',       false],
      ['returns false for Windows system',                    'mingw32',         false],
      ['returns false for Windows mswin variant',             'mswin',           false],
      ['returns false for cygwin environment',                'cygwin',          false],
      ['returns false for uppercase DARWIN (case sensitive)', 'DARWIN',          false],
      ['returns false for nil host_os',                       nil,               false],
      ['returns false for empty host_os',                     '',                false],
    ].map { |name, host_os, expected| { name:, host_os:, expected: } }

    detection_scenarios.each do |scenario|
      it scenario[:name] do
        stub_const('RbConfig::CONFIG', { 'host_os' => scenario[:host_os] })
        expect(os.current_os_is_this_os?).to eq(scenario[:expected])
      end
    end
  end

  describe '#create_model' do
    it 'delegates to MacOsModel.create_model and returns the model' do
      require_relative '../../../lib/wifi-wand/models/mac_os_model'
      options = { verbose: true, wifi_interface: 'en0' }
      mock_model = instance_double(WifiWand::MacOsModel)

      model_class = class_double(WifiWand::MacOsModel)
      stub_const('WifiWand::MacOsModel', model_class)
      expect(model_class).to receive(:create_model).with(options).and_return(mock_model)

      expect(os.create_model(options)).to eq(mock_model)
    end

    it 'passes through empty options' do
      require_relative '../../../lib/wifi-wand/models/mac_os_model'
      options = {}
      mock_model = instance_double(WifiWand::MacOsModel)

      model_class = class_double(WifiWand::MacOsModel)
      stub_const('WifiWand::MacOsModel', model_class)
      expect(model_class).to receive(:create_model).with(options).and_return(mock_model)

      expect(os.create_model(options)).to eq(mock_model)
    end

    it 'passes through nil options' do
      require_relative '../../../lib/wifi-wand/models/mac_os_model'
      options = nil
      mock_model = instance_double(WifiWand::MacOsModel)

      model_class = class_double(WifiWand::MacOsModel)
      stub_const('WifiWand::MacOsModel', model_class)
      expect(model_class).to receive(:create_model).with(options).and_return(mock_model)

      expect(os.create_model(options)).to eq(mock_model)
    end
  end
end
