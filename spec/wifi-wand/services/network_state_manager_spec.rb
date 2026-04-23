# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/network_state_manager'

describe WifiWand::NetworkStateManager do
  let(:mock_model) do
    double('Model',
      connected?:                 true,
      connection_ready?:          true,
      connection_security_type:   'WPA2',
      wifi_on?:                   true,
      mac?:                       false,
      connected_network_name:     'TestNetwork',
      wifi_interface:             'wlan0',
      preferred_network_password: 'testpass',
      wifi_on:                    nil,
      wifi_off:                   nil,
      connect:                    nil,
      till:                       nil
    )
  end

  let(:state_manager) { described_class.new(mock_model, verbose: false) }

  describe '#capture_network_state' do
    it 'captures current network state' do
      expect(mock_model).to receive(:preferred_network_password)
        .with('TestNetwork', timeout_in_secs: nil)
        .and_return('testpass')

      expect(state_manager.capture_network_state).to include(
        wifi_enabled:     true,
        network_name:     'TestNetwork',
        network_password: 'testpass',
        interface:        'wlan0'
      )
    end

    it 'handles nil connected network name' do
      allow(mock_model).to receive(:connected_network_name).and_return(nil)
      state = state_manager.capture_network_state
      expect(state[:network_name]).to be_nil
      expect(state[:network_password]).to be_nil
    end

    it 'handles password retrieval failure' do
      allow(mock_model).to receive_messages(
        connected_network_name: 'TestNetwork'
      )
      allow(mock_model).to receive(:preferred_network_password)
        .with('TestNetwork', timeout_in_secs: nil)
        .and_return(nil)
      state = state_manager.capture_network_state
      expect(state[:network_name]).to eq('TestNetwork')
      expect(state[:network_password]).to be_nil
    end

    it 'logs password retrieval failure in verbose mode' do
      output = StringIO.new
      verbose_manager = described_class.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      allow(mock_model).to receive(:preferred_network_password)
        .with('TestNetwork', timeout_in_secs: nil)
        .and_raise(WifiWand::KeychainError.new('Keychain error'))

      state = verbose_manager.capture_network_state
      expect(state[:network_password]).to be_nil
      expect(output.string).to match(/Warning: Failed to retrieve password for TestNetwork: Keychain error/)
    end
  end

  describe '#restore_network_state' do
    let(:valid_state) do
      {
        wifi_enabled:     true,
        network_name:     'TestNetwork',
        network_password: 'testpass',
        interface:        'wlan0',
      }
    end

    context 'with fail_silently: false' do
      it 'raises exceptions on wifi operation failures' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)
        allow(mock_model).to receive(:wifi_on).and_raise(WifiWand::WifiEnableError.new)

        expect do
          state_manager.restore_network_state(valid_state, fail_silently: false)
        end.to raise_error(WifiWand::WifiEnableError)
      end

      it 'raises exceptions on connection failures' do
        allow(mock_model).to receive_messages(
          connection_ready?:          false,
          wifi_on?:                   true,
          connected_network_name:     'OtherNetwork',
          preferred_network_password: 'testpass'
        )
        allow(mock_model).to receive(:connect).and_raise(
          network_connection_error(
            network_name: 'TestNetwork',
            reason:       'Network unavailable'
          )
        )
        allow(state_manager).to receive(:settle_for_restore?).and_return(false)

        expect do
          state_manager.restore_network_state(valid_state, fail_silently: false)
        end.to raise_error(WifiWand::NetworkConnectionError, /Network unavailable/)
      end
    end

    context 'with fail_silently: true' do
      it 'swallows wifi operation failures and logs to stderr' do
        allow(mock_model).to receive(:wifi_on?).and_return(false)
        allow(mock_model).to receive(:wifi_on).and_raise(WifiWand::WifiEnableError.new)

        target = 'Warning: Could not restore network state \(WifiWand::WifiEnableError\): ' \
          'WiFi could not be enabled.*' \
          'You may need to manually reconnect to: TestNetwork'
        expect { state_manager.restore_network_state(valid_state, fail_silently: true) }
          .to output(/#{target}/m).to_stdout
      end

      it 'swallows connection failures and logs to configured output' do
        output = StringIO.new
        manager = described_class.new(mock_model, verbose: false, output: output)
        allow(mock_model).to receive_messages(
          connection_ready?:          false,
          wifi_on?:                   true,
          connected_network_name:     'OtherNetwork',
          preferred_network_password: 'testpass'
        )
        allow(mock_model).to receive(:connect).and_raise(
          network_connection_error(
            network_name: 'TestNetwork',
            reason:       'Network unavailable'
          )
        )
        allow(mock_model).to receive(:till)
        allow(manager).to receive(:settle_for_restore?).and_return(false)

        manager.restore_network_state(valid_state, fail_silently: true)

        expect(output.string).to match(
          /Warning: Could not restore network state \(WifiWand::NetworkConnectionError\): Failed to connect/m
        )
        expect(output.string).to match(/You may need to manually reconnect to: TestNetwork/)
      end

      it 'swallows expected network errors and logs to configured output' do
        output = StringIO.new
        manager = described_class.new(mock_model, verbose: false, output: output)
        allow(mock_model).to receive_messages(
          connection_ready?:          false,
          wifi_on?:                   true,
          connected_network_name:     'OtherNetwork',
          preferred_network_password: 'testpass'
        )
        allow(mock_model).to receive(:connect).and_raise(SocketError, 'lookup failed')
        allow(manager).to receive(:settle_for_restore?).and_return(false)

        manager.restore_network_state(valid_state, fail_silently: true)

        expect(output.string).to match(
          /Warning: Could not restore network state \(SocketError\): lookup failed/
        )
        expect(output.string).to match(/You may need to manually reconnect to: TestNetwork/)
      end

      it 'propagates unexpected exceptions even when fail_silently is true' do
        allow(mock_model).to receive_messages(
          connection_ready?:          false,
          wifi_on?:                   true,
          connected_network_name:     'OtherNetwork',
          preferred_network_password: 'testpass'
        )
        allow(mock_model).to receive(:connect).and_raise(NoMethodError, 'unexpected bug')
        allow(state_manager).to receive(:settle_for_restore?).and_return(false)

        expect do
          state_manager.restore_network_state(valid_state, fail_silently: true)
        end.to raise_error(NoMethodError, 'unexpected bug')
      end
    end

    it 'returns :no_state_to_restore when state is nil' do
      expect(state_manager.restore_network_state(nil)).to eq(:no_state_to_restore)
    end

    it 'returns :already_connected when already on correct network' do
      allow(mock_model).to receive_messages(
        wifi_on?:          true,
        connection_ready?: true
      )
      expect(state_manager.restore_network_state(valid_state)).to eq(:already_connected)
    end

    it 'reconnects when SSID matches but the connection is not yet active' do
      allow(mock_model).to receive_messages(
        wifi_on?:               true,
        connected_network_name: 'TestNetwork'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false, true)
      allow(state_manager).to receive(:sleep)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)

      expect(mock_model).to receive(:connect).with('TestNetwork', 'testpass')

      state_manager.restore_network_state(valid_state)
    end

    it 'retries transient macOS networksetup restore failures' do
      transient_error = os_command_error(
        exitstatus: 1,
        command:    'networksetup',
        text:       "Failed to join network TestNetwork.\n" \
          "Error: -3900 The operation couldn't be completed. tmpErr"
      )
      allow(mock_model).to receive_messages(
        mac?:                   true,
        wifi_on?:               true,
        connected_network_name: 'OtherNetwork'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false, true)
      allow(mock_model).to receive(:associated?).and_return(false)
      allow(state_manager).to receive(:sleep)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)
      connect_attempts = 0
      allow(mock_model).to receive(:connect).with('TestNetwork', 'testpass') do
        connect_attempts += 1
        raise transient_error if connect_attempts == 1
      end

      state_manager.restore_network_state(valid_state)

      expect(mock_model).to have_received(:connect).twice
      expect(state_manager).to have_received(:sleep)
        .with(described_class::RESTORE_CONNECT_RETRY_WAIT_SECONDS)
    end

    it 'does not retry non-transient restore command failures' do
      permanent_error = os_command_error(
        exitstatus: 1,
        command:    'networksetup',
        text:       'Failed to join network TestNetwork. invalid parameter'
      )
      allow(mock_model).to receive_messages(
        mac?:                   true,
        connection_ready?:      false,
        wifi_on?:               true,
        connected_network_name: 'OtherNetwork'
      )
      allow(mock_model).to receive(:connect).with('TestNetwork', 'testpass')
        .and_raise(permanent_error)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)

      expect do
        state_manager.restore_network_state(valid_state)
      end.to raise_error(WifiWand::CommandExecutor::OsCommandError, /invalid parameter/)

      expect(mock_model).to have_received(:connect).once
    end

    it 'turns on WiFi when currently off but should be on' do
      wifi_off_state = valid_state.merge(wifi_enabled: true)
      allow(mock_model).to receive_messages(
        wifi_on?:               false,
        connected_network_name: 'TestNetwork'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false, true)
      allow(state_manager).to receive(:sleep)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)

      expect(mock_model).to receive(:wifi_on)
      expect(mock_model).to receive(:till)
        .with(:wifi_on, timeout_in_secs: WifiWand::TimingConstants::WIFI_STATE_CHANGE_WAIT)

      state_manager.restore_network_state(wifi_off_state)
    end

    it 'turns off WiFi when currently on but should be off and returns early' do
      wifi_off_state = valid_state.merge(wifi_enabled: false)
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(mock_model).to receive(:wifi_off)
      expect(mock_model).to receive(:till)
        .with(:wifi_off, timeout_in_secs: WifiWand::TimingConstants::WIFI_STATE_CHANGE_WAIT)
      expect(mock_model).not_to receive(:connect)

      state_manager.restore_network_state(wifi_off_state)
    end

    it 'uses fallback password when state password is nil' do
      state_without_password = valid_state.merge(network_password: nil)
      allow(mock_model).to receive_messages(
        wifi_on?:               true,
        connected_network_name: 'OtherNetwork'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false, true)
      allow(state_manager).to receive(:sleep)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork')
        .and_return('fallback_pass')

      expect(mock_model).to receive(:connect).with('TestNetwork', 'fallback_pass')

      state_manager.restore_network_state(state_without_password)
    end

    it 'skips network connection when WiFi should be disabled' do
      wifi_disabled_state = {
        wifi_enabled:     false,
        network_name:     'TestNetwork',
        network_password: 'testpass',
        interface:        'wlan0',
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
      allow(mock_model).to receive(:connected_network_name).and_return('ActualNetwork')
      allow(mock_model).to receive_messages(
        wifi_on?:                   true,
        preferred_network_password: 'testpass'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false)
      allow(mock_model).to receive(:connect)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
        .and_return(0.0, WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT + 1.0)

      expect do
        state_manager.restore_network_state(valid_state)
      end.to raise_error(WifiWand::NetworkConnectionError,
        /timed out waiting for connection; currently connected to "ActualNetwork"/)
    end

    it 'handles WaitTimeoutError when querying network name fails' do
      # First call (line 63 - already_connected check) returns different network
      # Second call (line 75 - in rescue block) raises error
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork',
        'OtherNetwork').and_raise(WifiWand::Error.new('Network query failed'))
      allow(mock_model).to receive_messages(
        wifi_on?:                   true,
        preferred_network_password: 'testpass'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false)
      allow(mock_model).to receive(:connect)
      allow(state_manager).to receive(:settle_for_restore?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
        .and_return(0.0, WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT + 1.0)

      expect do
        state_manager.restore_network_state(valid_state)
      end.to raise_error(WifiWand::NetworkConnectionError,
        /timed out waiting for connection; currently connected to nil/)
    end

    it 'logs WaitTimeoutError details in verbose mode when network query succeeds' do
      output = StringIO.new
      verbose_manager = described_class.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:connected_network_name).and_return('ActualNetwork')
      allow(mock_model).to receive_messages(
        wifi_on?:                   true,
        preferred_network_password: 'testpass'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false)
      allow(mock_model).to receive(:connect)
      allow(verbose_manager).to receive(:settle_for_restore?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
        .and_return(0.0, WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT + 1.0)

      expect do
        verbose_manager.restore_network_state(valid_state)
      end.to raise_error(WifiWand::NetworkConnectionError)
      expect(output.string).to match(
        /Warning: Connection timeout - expected "TestNetwork", currently connected to "ActualNetwork"/)
    end

    it 'logs WaitTimeoutError details in verbose mode when network query fails' do
      output = StringIO.new
      verbose_manager = described_class.new(mock_model, verbose: true, output: output)
      # First call (line 63 - already_connected check) returns different network
      # Second call (line 75 - in rescue block) raises error
      allow(mock_model).to receive(:connected_network_name).and_return('OtherNetwork',
        'OtherNetwork').and_raise(WifiWand::Error.new('Network query failed'))
      allow(mock_model).to receive_messages(
        wifi_on?:                   true,
        preferred_network_password: 'testpass'
      )
      allow(mock_model).to receive(:connection_ready?).and_return(false, false)
      allow(mock_model).to receive(:connect)
      allow(verbose_manager).to receive(:settle_for_restore?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
        .and_return(0.0, WifiWand::TimingConstants::NETWORK_CONNECTION_WAIT + 1.0)

      expect do
        verbose_manager.restore_network_state(valid_state)
      end.to raise_error(WifiWand::NetworkConnectionError)
      expect(output.string).to match(
        /Warning: Connection timeout and failed to query current network: Network query failed/)
    end
  end

  describe 'verbose mode' do
    let(:verbose_state_manager) { described_class.new(mock_model, verbose: true) }

    it 'logs restore attempts when verbose' do
      allow(mock_model).to receive_messages(wifi_on?: true, connected_network_name: 'TestNetwork')

      valid_state = {
        wifi_enabled:     true,
        network_name:     'TestNetwork',
        network_password: 'testpass',
        interface:        'wlan0',
      }

      expect do
        verbose_state_manager.restore_network_state(valid_state)
      end.to output(/restore_network_state: .* called/).to_stdout
    end
  end

  describe 'private helpers' do
    it 'fallback_password_for returns password when successful' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork')
        .and_return('test_password')
      expect(manager.send(:fallback_password_for, 'TestNetwork')).to eq('test_password')
    end

    it 'fallback_password_for returns nil when network_name is nil' do
      manager = described_class.new(mock_model)
      expect(manager.send(:fallback_password_for, nil)).to be_nil
    end

    it 'fallback_password_for rescues errors and returns nil' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive(:preferred_network_password)
        .and_raise(WifiWand::Error.new('Password lookup failed'))
      expect(manager.send(:fallback_password_for, 'TestNetwork')).to be_nil
    end

    it 'fallback_password_for logs errors in verbose mode' do
      output = StringIO.new
      verbose_manager = described_class.new(mock_model, verbose: true, output: output)
      allow(mock_model).to receive(:preferred_network_password)
        .and_raise(WifiWand::Error.new('Password lookup failed'))

      result = verbose_manager.send(:fallback_password_for, 'TestNetwork')
      expect(result).to be_nil
      expect(output.string).to match(
        /Warning: Failed to retrieve fallback password for TestNetwork: Password lookup failed/)
    end

    it 'connected_network_password returns password when network is connected' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive_messages(connected_network_name: 'CurrentNetwork',
        connection_security_type: 'WPA2')
      allow(mock_model).to receive(:preferred_network_password).with('CurrentNetwork', timeout_in_secs: nil)
        .and_return('current_password')
      expect(manager.send(:connected_network_password)).to eq('current_password')
    end

    it 'connected_network_password returns nil when not connected' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive(:connected_network_name).and_return(nil)
      expect(manager.send(:connected_network_password)).to be_nil
    end

    it 'connected_network_password attempts lookup when security type is nil (unknown)' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive_messages(connected_network_name: 'CurrentNetwork',
        connection_security_type: nil)
      allow(mock_model).to receive(:preferred_network_password).with('CurrentNetwork', timeout_in_secs: nil)
        .and_return(nil)

      # nil means macOS could not report the security type; attempt lookup rather
      # than silently skipping it, in case the network is password-protected.
      expect(mock_model).to receive(:preferred_network_password)

      manager.send(:connected_network_password)
    end

    it 'connected_network_password skips lookup for open networks (NONE)' do
      manager = described_class.new(mock_model)
      allow(mock_model).to receive_messages(connected_network_name: 'OpenNetwork',
        connection_security_type: 'NONE')

      expect(mock_model).not_to receive(:preferred_network_password)

      expect(manager.send(:connected_network_password)).to be_nil
    end
  end
end
