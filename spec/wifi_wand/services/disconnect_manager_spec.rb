# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/services/disconnect_manager'

describe WifiWand::DisconnectManager do
  subject(:disconnect_manager) { described_class.new(model) }

  let(:test_model_class) do
    klass = Class.new(WifiWand::BaseModel) do
      def self.os_id = :mac
    end

    define_base_model_required_methods(klass, probe_wifi_interface: 'en0')
  end

  let(:model) { test_model_class.new }

  describe '#disconnect' do
    it 'raises a dedicated error when the interface remains associated' do
      allow(model).to receive_messages(
        wifi_on?:               true,
        connected_network_name: 'TestNet'
      )
      allow(model).to receive(:_disconnect)
      allow(disconnect_manager).to receive(:wait_until_disassociated!)
        .and_raise(wait_timeout_error(action: :disassociated, timeout: 5))

      expect { disconnect_manager.disconnect }
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

      expect { disconnect_manager.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
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
      allow(disconnect_manager).to receive(:wait_until_disassociated!)
      allow(model).to receive(:_disconnect)
        .and_raise(os_command_error(
          exitstatus: 1,
          command:    'disconnect current network',
          text:       'disconnect failed'
        ))

      expect { disconnect_manager.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('disconnect failed')
        expect(error.reason).to include('disconnect current network')
      end
      expect(model).to have_received(:_disconnect)
      expect(disconnect_manager).not_to have_received(:wait_until_disassociated!)
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

      expect { disconnect_manager.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to be_nil
        expect(error.reason).to include('NetworkManager unavailable')
        expect(error.reason).to include('nmcli connection show --active')
      end
      expect(model).not_to have_received(:_disconnect)
    end

    it 'reports verification probe command failures as disconnection errors' do
      allow(model).to receive_messages(wifi_on?: true, connected_network_name: 'TestNet')
      allow(model).to receive(:_disconnect)
      allow(disconnect_manager).to receive(:wait_until_disassociated!)
        .and_raise(os_command_error(
          exitstatus: 1,
          command:    'nmcli connection show --active',
          text:       'probe failed during verification'
        ))

      expect { disconnect_manager.disconnect }.to raise_error(WifiWand::NetworkDisconnectionError) do |error|
        expect(error.network_name).to eq('TestNet')
        expect(error.reason).to include('probe failed during verification')
        expect(error.reason).to include('nmcli connection show --active')
      end
    end

    it 'raises when disassociation is not stable after the initial wait succeeds' do
      allow(model).to receive_messages(
        wifi_on?:               true,
        connected_network_name: 'TestNet'
      )
      allow(model).to receive(:_disconnect)
      allow(disconnect_manager).to receive_messages(
        disconnect_stability_window_in_secs: 0.1,
        wait_until_disassociated!:           nil,
        disassociated_stable?:               false
      )

      expect { disconnect_manager.disconnect }
        .to raise_error(WifiWand::NetworkDisconnectionError, /still associated with 'TestNet'/)
    end

    it 'is a no-op when wifi is already disassociated' do
      allow(model).to receive_messages(wifi_on?: true, connected_network_name: nil, connected?: false)
      allow(disconnect_manager).to receive(:wait_until_disassociated!)
      allow(model).to receive(:_disconnect)

      expect(disconnect_manager.disconnect).to be_nil
      expect(model).not_to have_received(:_disconnect)
      expect(disconnect_manager).not_to have_received(:wait_until_disassociated!)
    end
  end

  describe '#disconnect_stability_window_in_secs' do
    it 'defaults to two ordinary wait intervals' do
      expect(disconnect_manager.disconnect_stability_window_in_secs)
        .to eq(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL * 2)
    end
  end

  describe '#disassociated_stable?' do
    it 'returns true once the interface stays disassociated through the stability window' do
      allow(disconnect_manager).to receive_messages(
        disconnect_stability_window_in_secs: 0.2,
        disconnect_association_state:        { associated: false, network_name: nil }
      )
      allow(disconnect_manager).to receive(:monotonic_now).and_return(10.0, 10.1, 10.2)
      allow(disconnect_manager).to receive(:sleep)

      expect(disconnect_manager.disassociated_stable?).to be(true)
      expect(disconnect_manager).to have_received(:sleep)
        .with(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL).once
    end

    it 'returns false when the interface is still associated at the start of the stability window' do
      allow(disconnect_manager).to receive_messages(
        disconnect_stability_window_in_secs: 0.2,
        disconnect_association_state:        { associated: true, network_name: 'TestNet' }
      )
      allow(disconnect_manager).to receive(:monotonic_now).and_return(10.0)
      allow(disconnect_manager).to receive(:sleep)

      expect(disconnect_manager.disassociated_stable?).to be(false)
      expect(disconnect_manager).not_to have_received(:sleep)
    end
  end
end
