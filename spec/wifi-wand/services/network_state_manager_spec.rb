require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/network_state_manager'

describe WifiWand::NetworkStateManager do
  let(:mock_model) do
    double('Model',
      wifi_on?: true,
      connected_network_name: 'TestNetwork',
      wifi_interface: 'wlan0',
      preferred_network_password: 'testpass',
      wifi_on: nil,
      wifi_off: nil,
      connect: nil,
      till: nil
    )
  end

  let(:state_manager) { WifiWand::NetworkStateManager.new(mock_model, verbose: false) }

  describe '#capture_network_state' do
    it 'captures current network state' do
      expect(state_manager.capture_network_state).to include(
        wifi_enabled: true,
        network_name: 'TestNetwork',
        network_password: 'testpass',
        interface: 'wlan0'
      )
    end

    it 'handles nil connected network name' do
      allow(mock_model).to receive(:connected_network_name).and_return(nil)
      state = state_manager.capture_network_state
      expect(state[:network_name]).to be_nil
      expect(state[:network_password]).to be_nil
    end
  end

  describe '#restore_network_state' do
    let(:valid_state) do
      {
        wifi_enabled: true,
        network_name: 'TestNetwork',
        network_password: 'testpass',
        interface: 'wlan0'
      }
    end

    context 'with fail_silently: false' do
      it 'raises exceptions on wifi operation failures' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)
        allow(mock_model).to receive(:wifi_on).and_raise(StandardError.new('WiFi hardware error'))

        expect {
          state_manager.restore_network_state(valid_state, fail_silently: false)
        }.to raise_error(StandardError, 'WiFi hardware error')
      end

      it 'raises exceptions on connection failures' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork')
        allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
        allow(mock_model).to receive(:connect).and_raise(StandardError.new('Network unavailable'))

        expect {
          state_manager.restore_network_state(valid_state, fail_silently: false)
        }.to raise_error(StandardError, 'Network unavailable')
      end
    end

    context 'with fail_silently: true' do
      it 'swallows wifi operation failures and logs to stderr' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)
        allow(mock_model).to receive(:wifi_on).and_raise(StandardError.new('WiFi hardware error'))

        expect($stderr).to receive(:puts).with('Warning: Could not restore network state: WiFi hardware error')
        expect($stderr).to receive(:puts).with('You may need to manually reconnect to: TestNetwork')

        expect {
          state_manager.restore_network_state(valid_state, fail_silently: true)
        }.not_to raise_error
      end

      it 'swallows connection failures and logs to stderr' do
        allow(mock_model).to receive(:wifi_on?).and_return(true)
        allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork')
        allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
        allow(mock_model).to receive(:connect).and_raise(StandardError.new('Network unavailable'))
        allow(mock_model).to receive(:till)

        expect($stderr).to receive(:puts).with('Warning: Could not restore network state: Network unavailable')
        expect($stderr).to receive(:puts).with('You may need to manually reconnect to: TestNetwork')

        expect {
          state_manager.restore_network_state(valid_state, fail_silently: true)
        }.not_to raise_error
      end
    end

    it 'returns :no_state_to_restore when state is nil' do
      expect(state_manager.restore_network_state(nil)).to eq(:no_state_to_restore)
    end

    it 'returns :already_connected when already on correct network' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(state_manager.restore_network_state(valid_state)).to eq(:already_connected)
    end

  end

  describe 'verbose mode' do
    let(:verbose_state_manager) { WifiWand::NetworkStateManager.new(mock_model, verbose: true) }

    it 'logs restore attempts when verbose' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')

      valid_state = {
        wifi_enabled: true,
        network_name: 'TestNetwork',
        network_password: 'testpass',
        interface: 'wlan0'
      }

      expect { 
        verbose_state_manager.restore_network_state(valid_state) 
      }.to output(/restore_network_state: .* called/).to_stdout
    end
  end
end