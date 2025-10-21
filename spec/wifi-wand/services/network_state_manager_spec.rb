# frozen_string_literal: true

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

    it 'handles password retrieval failure' do
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      allow(mock_model).to receive(:preferred_network_password).and_return(nil)
      state = state_manager.capture_network_state
      expect(state[:network_name]).to eq('TestNetwork')
      expect(state[:network_password]).to be_nil
    end

    it 'logs password retrieval failure in verbose mode' do
      output = StringIO.new
      verbose_manager = WifiWand::NetworkStateManager.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      allow(mock_model).to receive(:preferred_network_password).and_raise(StandardError.new('Keychain error'))

      state = verbose_manager.capture_network_state
      expect(state[:network_password]).to be_nil
      expect(output.string).to match(/Warning: Failed to retrieve password for TestNetwork: Keychain error/)
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

    it 'turns on WiFi when currently off but should be on' do
      wifi_off_state = valid_state.merge(wifi_enabled: true)
      allow(mock_model).to receive(:wifi_on?).and_return(false)
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      
      expect(mock_model).to receive(:wifi_on)
      expect(mock_model).to receive(:till).with(:on, timeout_in_secs: WifiWand::TimingConstants::WIFI_STATE_CHANGE_WAIT)
      
      state_manager.restore_network_state(wifi_off_state)
    end

    it 'turns off WiFi when currently on but should be off and returns early' do
      wifi_off_state = valid_state.merge(wifi_enabled: false)
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      
      expect(mock_model).to receive(:wifi_off)
      expect(mock_model).to receive(:till).with(:off, timeout_in_secs: WifiWand::TimingConstants::WIFI_STATE_CHANGE_WAIT)
      expect(mock_model).not_to receive(:connect)
      
      state_manager.restore_network_state(wifi_off_state)
    end

    it 'uses fallback password when state password is nil' do
      state_without_password = valid_state.merge(network_password: nil)
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork')
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('fallback_pass')
      
      expect(mock_model).to receive(:connect).with('TestNetwork', 'fallback_pass')
      expect(mock_model).to receive(:till).with(:conn, timeout_in_secs: WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT)
      
      state_manager.restore_network_state(state_without_password)
    end

    it 'skips network connection when WiFi should be disabled' do
      wifi_disabled_state = {
        wifi_enabled: false,
        network_name: 'TestNetwork',
        network_password: 'testpass',
        interface: 'wlan0'
      }
      allow(mock_model).to receive(:wifi_on?).and_return(false)
      
      expect(mock_model).not_to receive(:connect)
      expect(mock_model).not_to receive(:wifi_on)
      expect(mock_model).not_to receive(:wifi_off)
      
      state_manager.restore_network_state(wifi_disabled_state)
    end

    it 'skips network connection when no network name in state' do
      state_no_network = valid_state.merge(network_name: nil)
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(mock_model).not_to receive(:connect)

      state_manager.restore_network_state(state_no_network)
    end

    it 'handles WaitTimeoutError and queries current network name' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork', 'ActualNetwork')
      allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
      allow(mock_model).to receive(:connect)
      allow(mock_model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:conn, 10))

      expect {
        state_manager.restore_network_state(valid_state)
      }.to raise_error(WifiWand::NetworkConnectionError, /timed out waiting for connection; currently connected to "ActualNetwork"/)
    end

    it 'handles WaitTimeoutError when querying network name fails' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      # First call (line 63 - already_connected check) returns different network
      # Second call (line 75 - in rescue block) raises error
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork', 'OtherNetwork').and_raise(StandardError.new('Network query failed'))
      allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
      allow(mock_model).to receive(:connect)
      allow(mock_model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:conn, 10))

      expect {
        state_manager.restore_network_state(valid_state)
      }.to raise_error(WifiWand::NetworkConnectionError, /timed out waiting for connection; currently connected to nil/)
    end

    it 'logs WaitTimeoutError details in verbose mode when network query succeeds' do
      output = StringIO.new
      verbose_manager = WifiWand::NetworkStateManager.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork', 'ActualNetwork')
      allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
      allow(mock_model).to receive(:connect)
      allow(mock_model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:conn, 10))

      expect {
        verbose_manager.restore_network_state(valid_state)
      }.to raise_error(WifiWand::NetworkConnectionError)
      expect(output.string).to match(/Warning: Connection timeout - expected "TestNetwork", currently connected to "ActualNetwork"/)
    end

    it 'logs WaitTimeoutError details in verbose mode when network query fails' do
      output = StringIO.new
      verbose_manager = WifiWand::NetworkStateManager.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:wifi_on?).and_return(true)
      # First call (line 63 - already_connected check) returns different network
      # Second call (line 75 - in rescue block) raises error
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork', 'OtherNetwork').and_raise(StandardError.new('Network query failed'))
      allow(mock_model).to receive(:preferred_network_password).and_return('testpass')
      allow(mock_model).to receive(:connect)
      allow(mock_model).to receive(:till).and_raise(WifiWand::WaitTimeoutError.new(:conn, 10))

      expect {
        verbose_manager.restore_network_state(valid_state)
      }.to raise_error(WifiWand::NetworkConnectionError)
      expect(output.string).to match(/Warning: Connection timeout and failed to query current network: Network query failed/)
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

  describe 'private helpers' do
    it 'fallback_password_for returns password when successful' do
      manager = WifiWand::NetworkStateManager.new(mock_model)
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('test_password')
      expect(manager.send(:fallback_password_for, 'TestNetwork')).to eq('test_password')
    end

    it 'fallback_password_for returns nil when network_name is nil' do
      manager = WifiWand::NetworkStateManager.new(mock_model)
      expect(manager.send(:fallback_password_for, nil)).to be_nil
    end

    it 'fallback_password_for rescues errors and returns nil' do
      manager = WifiWand::NetworkStateManager.new(mock_model)
      allow(mock_model).to receive(:preferred_network_password).and_raise(StandardError.new('Password lookup failed'))
      expect(manager.send(:fallback_password_for, 'TestNetwork')).to be_nil
    end

    it 'fallback_password_for logs errors in verbose mode' do
      output = StringIO.new
      verbose_manager = WifiWand::NetworkStateManager.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:preferred_network_password).and_raise(StandardError.new('Password lookup failed'))

      result = verbose_manager.send(:fallback_password_for, 'TestNetwork')
      expect(result).to be_nil
      expect(output.string).to match(/Warning: Failed to retrieve fallback password for TestNetwork: Password lookup failed/)
    end

    it 'connected_network_password returns password when network is connected' do
      manager = WifiWand::NetworkStateManager.new(mock_model)
      allow(mock_model).to receive(:connected_network_name).and_return('CurrentNetwork')
      allow(mock_model).to receive(:preferred_network_password).with('CurrentNetwork').and_return('current_password')
      expect(manager.send(:connected_network_password)).to eq('current_password')
    end

    it 'connected_network_password returns nil when not connected' do
      manager = WifiWand::NetworkStateManager.new(mock_model)
      allow(mock_model).to receive(:connected_network_name).and_return(nil)
      expect(manager.send(:connected_network_password)).to be_nil
    end
  end
end
