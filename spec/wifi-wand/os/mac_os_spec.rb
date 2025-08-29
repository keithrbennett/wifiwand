require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/os/mac_os'

module WifiWand

describe MacOs do
  subject { MacOs.new }

  describe '#initialize' do
    it 'sets correct id and display_name' do
      expect(subject.id).to eq(:mac)
      expect(subject.display_name).to eq('macOS')
    end
  end

  describe '#current_os_is_this_os?' do
    detection_scenarios = [
      {
        name: 'detects macOS with darwin host_os',
        host_os: 'darwin',
        expected: true
      },
      {
        name: 'detects macOS with darwin-based host_os',
        host_os: 'x86_64-darwin21',
        expected: true
      },
      {
        name: 'returns false for Linux system',
        host_os: 'linux-gnu',
        expected: false
      },
      {
        name: 'returns false for Windows system',
        host_os: 'mingw32',
        expected: false
      },
      {
        name: 'returns false for uppercase DARWIN (case sensitive)',
        host_os: 'DARWIN',
        expected: false
      }
    ]

    detection_scenarios.each do |scenario|
      it scenario[:name] do
        stub_const('RbConfig::CONFIG', { 'host_os' => scenario[:host_os] })
        expect(subject.current_os_is_this_os?).to be scenario[:expected]
      end
    end
  end

  describe '#create_model' do
    it 'requires MacOsModel and creates model with options' do
      options = { verbose: true, wifi_interface: 'en0' }
      mock_model = double('MacOsModel')
      
      expect(subject).to receive(:require_relative).with('../models/mac_os_model')
      stub_const('WifiWand::MacOsModel', double('MacOsModelClass'))
      expect(WifiWand::MacOsModel).to receive(:create_model).with(options).and_return(mock_model)
      
      expect(subject.create_model(options)).to eq(mock_model)
    end
  end
end

end