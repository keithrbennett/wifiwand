require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/os/ubuntu'

module WifiWand

describe Ubuntu do
  subject { Ubuntu.new }

  describe '#initialize' do
    it 'sets correct id and display_name' do
      expect(subject.id).to eq(:ubuntu)
      expect(subject.display_name).to eq('Ubuntu Linux')
    end
  end

  describe '#current_os_is_this_os?' do
    detection_scenarios = [
      {
        name: 'detects Ubuntu via /etc/os-release',
        os_release_exists: true,
        os_release_content: "ID=ubuntu\n",
        lsb_release_result: false,
        proc_version_exists: false,
        host_os: 'linux-gnu',
        expected: true
      },
      {
        name: 'detects Ubuntu via lsb_release command',
        os_release_exists: false,
        lsb_release_result: true,
        proc_version_exists: false,
        host_os: 'linux-gnu',
        expected: true
      },
      {
        name: 'detects Ubuntu via /proc/version',
        os_release_exists: false,
        lsb_release_result: false,
        proc_version_exists: true,
        proc_version_content: "Linux version 5.4.0-74-generic #83-Ubuntu",
        host_os: 'linux-gnu',
        expected: true
      },
      {
        name: 'falls back to Linux detection via RbConfig',
        os_release_exists: false,
        lsb_release_result: false,
        proc_version_exists: false,
        host_os: 'linux-gnu',
        expected: true
      },
      {
        name: 'returns false on non-Linux system',
        os_release_exists: false,
        lsb_release_result: false,
        proc_version_exists: false,
        host_os: 'darwin',
        expected: false
      },
      {
        name: 'falls back when os-release is not Ubuntu',
        os_release_exists: true,
        os_release_content: "ID=debian\n",
        lsb_release_result: false,
        proc_version_exists: false,
        host_os: 'linux-gnu',
        expected: true
      }
    ]

    detection_scenarios.each do |scenario|
      it scenario[:name] do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:read).and_call_original
        
        allow(File).to receive(:exist?).with('/etc/os-release').and_return(scenario[:os_release_exists])
        if scenario[:os_release_exists] && scenario[:os_release_content]
          allow(File).to receive(:read).with('/etc/os-release').and_return(scenario[:os_release_content])
        end
        
        allow(subject).to receive(:system).with('lsb_release -i 2>/dev/null | grep -q "Ubuntu"').and_return(scenario[:lsb_release_result])
        
        allow(File).to receive(:exist?).with('/proc/version').and_return(scenario[:proc_version_exists])
        if scenario[:proc_version_exists] && scenario[:proc_version_content]
          allow(File).to receive(:read).with('/proc/version').and_return(scenario[:proc_version_content])
        end
        
        stub_const('RbConfig::CONFIG', { 'host_os' => scenario[:host_os] })
        
        expect(subject.current_os_is_this_os?).to be scenario[:expected]
      end
    end
  end

  describe '#create_model' do
    it 'requires UbuntuModel and creates model with options' do
      options = { verbose: true, wifi_interface: 'wlan0' }
      mock_model = double('UbuntuModel')
      
      expect(subject).to receive(:require_relative).with('../models/ubuntu_model')
      stub_const('WifiWand::UbuntuModel', double('UbuntuModelClass'))
      expect(WifiWand::UbuntuModel).to receive(:create_model).with(options).and_return(mock_model)
      
      expect(subject.create_model(options)).to eq(mock_model)
    end
  end
end

end