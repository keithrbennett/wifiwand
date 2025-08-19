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

    it 'restores wifi off state correctly' do
      wifi_off_state = valid_state.merge(wifi_enabled: false)
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(mock_model).to receive(:wifi_off)
      expect(mock_model).to receive(:till).with(:off, 0.05)

      state_manager.restore_network_state(wifi_off_state)
    end

    it 'restores wifi on state correctly when wifi is off' do
      allow(mock_model).to receive(:wifi_on?).and_return(false, true)  # First false, then true after wifi_on
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:wifi_on)
      expect(mock_model).to receive(:till).with(:on, 0.05)
      expect(state_manager.restore_network_state(valid_state)).to eq(:already_connected)
    end

    it 'connects to specified network when not already connected' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('DifferentNetwork')
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('testpass')

      expect(mock_model).to receive(:connect).with('TestNetwork', 'testpass')
      expect(mock_model).to receive(:till).with(:conn, 0.25)

      state_manager.restore_network_state(valid_state)
    end

    it 'uses provided password when available' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('DifferentNetwork')

      expect(mock_model).to receive(:connect).with('TestNetwork', 'testpass')
      expect(mock_model).to receive(:till).with(:conn, 0.25)

      state_manager.restore_network_state(valid_state)
    end

    it 'falls back to preferred network password when state password is nil' do
      state_without_password = valid_state.merge(network_password: nil)
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('DifferentNetwork')
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('fallback_password')

      expect(mock_model).to receive(:connect).with('TestNetwork', 'fallback_password')
      expect(mock_model).to receive(:till).with(:conn, 0.25)

      state_manager.restore_network_state(state_without_password)
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