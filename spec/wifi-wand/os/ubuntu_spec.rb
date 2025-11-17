# frozen_string_literal: true

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
        name: 'detects Ubuntu via /etc/os-release with ID=ubuntu',
        os_release_exists: true,
        os_release_content: "ID=ubuntu\nID_LIKE=debian\n",
        proc_version_exists: false,
        expected: true
      },
      {
        name: 'detects Ubuntu derivatives via ID_LIKE=ubuntu',
        os_release_exists: true,
        os_release_content: "ID=linuxmint\nID_LIKE=ubuntu\n",
        proc_version_exists: false,
        expected: true
      },
      {
        name: 'detects Ubuntu derivatives via ID_LIKE="ubuntu debian"',
        os_release_exists: true,
        os_release_content: "ID=pop\nID_LIKE=\"ubuntu debian\"\n",
        proc_version_exists: false,
        expected: true
      },
      {
        name: 'detects Ubuntu via /proc/version when os-release absent',
        os_release_exists: false,
        proc_version_exists: true,
        proc_version_content: "Linux version 5.4.0-74-generic #83-Ubuntu",
        expected: true
      },
      {
        name: 'returns false for Debian (ID=debian without ubuntu in ID_LIKE)',
        os_release_exists: true,
        os_release_content: "ID=debian\n",
        proc_version_exists: false,
        expected: false
      },
      {
        name: 'returns false for Fedora',
        os_release_exists: true,
        os_release_content: "ID=fedora\nID_LIKE=\"rhel fedora\"\n",
        proc_version_exists: false,
        expected: false
      },
      {
        name: 'returns false when no Ubuntu indicators found',
        os_release_exists: false,
        proc_version_exists: false,
        expected: false
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

        allow(File).to receive(:exist?).with('/proc/version').and_return(scenario[:proc_version_exists])
        if scenario[:proc_version_exists] && scenario[:proc_version_content]
          allow(File).to receive(:read).with('/proc/version').and_return(scenario[:proc_version_content])
        end

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