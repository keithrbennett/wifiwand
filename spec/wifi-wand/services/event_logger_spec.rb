# frozen_string_literal: true

require 'tempfile'
require 'timeout'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/event_logger'
require_relative '../../../lib/wifi-wand/services/log_file_manager'

describe WifiWand::EventLogger do
  ISO8601_TIMESTAMP_PATTERN = '\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]'

  let(:mock_model) do
    double('Model',
      internet_connectivity_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
      connected?:                  true,
      wifi_on?:                    true,
      connected_network_name:      'TestNetwork'
    )
  end
  let(:out_stream) { StringIO.new }
  let(:mock_log_file_manager) { double('LogFileManager', write: nil, close: nil) }

  describe 'initialization' do
    it 'creates an instance with default values' do
      logger = described_class.new(mock_model)
      expect(logger.model).to eq(mock_model)
      expect(logger.interval).to eq(5)
      expect(logger.verbose?).to be false
    end

    it 'accepts custom interval' do
      logger = described_class.new(mock_model, interval: 10)
      expect(logger.interval).to eq(10)
    end

    it 'accepts verbose flag' do
      logger = described_class.new(mock_model, verbose: true)
      expect(logger.verbose?).to be true
    end

    it 'reads verbose from shared runtime config after initialization' do
      runtime_config = WifiWand::RuntimeConfig.new(verbose: false, out_stream: out_stream)
      logger = described_class.new(mock_model, runtime_config: runtime_config)

      runtime_config.verbose = true
      fetch_failures = []

      logger.send(:fetch_status_value, :wifi_on, nil, fetch_failures) do
        raise WifiWand::Error, 'boom'
      end

      expect(out_stream.string).to include('Error fetching wifi_on: boom')
    end

    it 'uses an explicit verbose override without mutating shared runtime config' do
      runtime_config = WifiWand::RuntimeConfig.new(verbose: false, out_stream: out_stream)
      logger = described_class.new(mock_model, runtime_config: runtime_config, verbose: true)

      expect(logger.verbose?).to be true
      expect(runtime_config.verbose).to be false
    end

    it 'reads out_stream from shared runtime config after initialization' do
      initial_output = StringIO.new
      updated_output = StringIO.new
      runtime_config = WifiWand::RuntimeConfig.new(verbose: true, out_stream: initial_output)
      logger = described_class.new(mock_model, runtime_config: runtime_config)

      runtime_config.out_stream = updated_output
      logger.send(:log_message, 'updated destination')

      expect(initial_output.string).to be_empty
      expect(updated_output.string).to include('updated destination')
    end

    it 'does not create LogFileManager when no file path specified (stdout-only mode)' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      expect(logger.log_file_manager).to be_nil
    end

    it 'creates LogFileManager when file path specified' do
      Dir.mktmpdir do |dir|
        log_file_path = File.join(dir, 'test.log')
        logger = described_class.new(mock_model, log_file_path: log_file_path, out_stream: out_stream)
        expect(logger.log_file_manager).to be_a(WifiWand::LogFileManager)
        logger.cleanup
      end
    end

    it 'accepts custom LogFileManager' do
      logger = described_class.new(mock_model, log_file_manager: mock_log_file_manager)
      expect(logger.log_file_manager).to eq(mock_log_file_manager)
    end

    it 'respects nil output (file-only mode, no stdout)' do
      Dir.mktmpdir do |dir|
        log_file_path = File.join(dir, 'test.log')
        logger = described_class.new(
          mock_model,
          log_file_path:    log_file_path,
          out_stream:       nil,
          log_file_manager: mock_log_file_manager
        )
        expect(logger.out_stream).to be_nil
        # Verify log_message doesn't call puts when output is nil
        expect { logger.send(:log_message, 'test message') }.not_to raise_error
        expect(mock_log_file_manager).to have_received(:write).with('test message')
      end
    end
  end

  describe '#fetch_current_state' do
    it 'uses the full explicit probe at startup before any previous state exists' do
      logger = described_class.new(mock_model, out_stream: out_stream)

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'builds state from WiFi, association, SSID, and explicit internet state' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      state = {
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
      }

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)
      expect(mock_model).not_to receive(:status_line_data)

      expect(logger.send(:fetch_current_state)).to eq(state)
    end

    [
      'treats DNS failure with TCP still reachable as internet unavailable',
      'treats captive portal sessions as internet unavailable',
    ].each do |description|
      it description do
        logger = described_class.new(mock_model, out_stream: out_stream)

        expect(mock_model).to receive(:wifi_on?).and_return(true)
        expect(mock_model).to receive(:connected?).and_return(true)
        expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
        expect(mock_model).to receive(:internet_connectivity_state)
          .with(timeout_in_secs: 1.0)
          .and_return(WifiWand::ConnectivityStates::INTERNET_UNREACHABLE)

        expect(logger.send(:fetch_current_state)).to eq(
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE
        )
      end
    end

    it 'still checks internet state when WiFi is off' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      state = {
        wifi_on:        false,
        connected:      false,
        network_name:   nil,
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
      }

      expect(mock_model).to receive(:wifi_on?).and_return(false)
      expect(mock_model).not_to receive(:connected_network_name)
      expect(mock_model).not_to receive(:connected?)
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)
      expect(mock_model).not_to receive(:status_line_data)

      expect(logger.send(:fetch_current_state)).to eq(state)
    end

    it 'still checks internet state when WiFi is on but not connected' do
      logger = described_class.new(mock_model, out_stream: out_stream)

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(false)
      expect(mock_model).not_to receive(:connected_network_name)
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      false,
        network_name:   nil,
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'calls the full explicit probe on every poll when the previous internet state was reachable' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.5)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 0.5)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'calls the full explicit probe on every poll when the previous internet state was unreachable' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.5)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 0.5)
        .and_return(WifiWand::ConnectivityStates::INTERNET_UNREACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE
      )
    end

    it 'calls the full explicit probe on every poll when the previous internet state was indeterminate' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.5)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_INDETERMINATE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 0.5)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'still calls the full explicit probe when the previous internet state was pending' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.5)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_PENDING,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 0.5)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'degrades to the previous internet state when that lookup fails' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'PreviousNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_raise(WifiWand::Error, 'internet probe failed')

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE
      )
    end

    it 'logs field-level failures in verbose mode while returning partial state' do
      logger = described_class.new(mock_model, out_stream: out_stream, verbose: true)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'PreviousNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_raise(WifiWand::Error, 'Test error')
      expect(mock_model).not_to receive(:connected_network_name)
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)
      expect(logger).to receive(:log_message).with(/Error fetching connected: Test error/)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'PreviousNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 're-raises programmer bugs instead of degrading them' do
      logger = described_class.new(mock_model, out_stream: out_stream)

      expect(mock_model).to receive(:wifi_on?).and_raise(NoMethodError, 'undefined helper')

      expect { logger.send(:fetch_current_state) }.to raise_error(NoMethodError, /undefined helper/)
    end

    it 'preserves the previous SSID when connected state falls back' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'PreviousNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE,
        })

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_raise(WifiWand::Error, 'association probe failed')
      expect(mock_model).not_to receive(:connected_network_name)
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'PreviousNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'preserves connected state when SSID lookup returns nil' do
      logger = described_class.new(mock_model, out_stream: out_stream)

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return(nil)
      expect(mock_model).to receive(:internet_connectivity_state)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   '[SSID unavailable]',
        internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE
      )
    end

    it 'preserves an indeterminate startup internet state' do
      logger = described_class.new(mock_model, out_stream: out_stream)

      expect(mock_model).to receive(:wifi_on?).and_return(true)
      expect(mock_model).to receive(:connected?).and_return(true)
      expect(mock_model).to receive(:connected_network_name).and_return('TestNetwork')
      expect(mock_model).to receive(:internet_connectivity_state)
        .with(timeout_in_secs: 1.0)
        .and_return(WifiWand::ConnectivityStates::INTERNET_INDETERMINATE)

      expect(logger.send(:fetch_current_state)).to eq(
        wifi_on:        true,
        connected:      true,
        network_name:   'TestNetwork',
        internet_state: WifiWand::ConnectivityStates::INTERNET_INDETERMINATE
      )
    end

    it 'warns once after repeated failures in normal mode and resets after recovery' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      logger.instance_variable_set(:@previous_state,
        {
          wifi_on:        true,
          connected:      true,
          network_name:   'PreviousNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_UNREACHABLE,
        })

      allow(mock_model).to receive_messages(
        wifi_on?:               true,
        connected?:             true,
        connected_network_name: 'TestNetwork'
      )
      allow(mock_model).to receive(:internet_connectivity_state)
        .and_raise(WifiWand::Error, 'internet probe failed')

      3.times { logger.send(:fetch_current_state) }
      warning = [
        'WARNING: Status polling is encountering repeated lookup failures.',
        'Continuing with partial state until lookups recover.',
      ].join(' ')
      expect(out_stream.string.scan(warning).length).to eq(1)

      allow(mock_model).to receive(:internet_connectivity_state)
        .and_return(WifiWand::ConnectivityStates::INTERNET_REACHABLE)
      logger.send(:fetch_current_state)
      allow(mock_model).to receive(:internet_connectivity_state)
        .and_raise(WifiWand::Error, 'internet probe failed')

      2.times { logger.send(:fetch_current_state) }
      expect(out_stream.string.scan(warning).length).to eq(2)
    end
  end

  describe '#current_network_name' do
    let(:logger) { described_class.new(mock_model, out_stream: out_stream) }

    it 'returns the actual SSID when one is available' do
      allow(mock_model).to receive(:connected_network_name).and_return('TestNetwork')

      expect(logger.send(:current_network_name, true)).to eq('TestNetwork')
    end

    it 'returns the degraded placeholder when connected but the SSID is unavailable' do
      allow(mock_model).to receive(:connected_network_name).and_return(nil)

      expect(logger.send(:current_network_name, true)).to eq('[SSID unavailable]')
    end

    it 'returns nil when disconnected and the SSID is unavailable' do
      allow(mock_model).to receive(:connected_network_name).and_return(nil)

      expect(logger.send(:current_network_name, false)).to be_nil
    end
  end

  describe '#detect_and_emit_events' do
    let(:logger) do
      described_class.new(
        mock_model,
        out_stream:       out_stream,
        log_file_manager: mock_log_file_manager
      )
    end

    it 'does not emit events on first call (no previous state)' do
      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }
      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_on event when WiFi is turned on' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable })

      current_state = { wifi_on: true, connected: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:wifi_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit wifi events when the current WiFi state is unknown' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state =
        { wifi_on: nil, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).not_to receive(:emit_event).with(:wifi_on, anything, anything, anything)
      expect(logger).not_to receive(:emit_event).with(:wifi_off, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_off event when WiFi is turned off' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: false, network_name: nil, internet_state: :unreachable })

      current_state = { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:wifi_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits connected event when network is joined' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: false, network_name: nil, internet_state: :reachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits disconnected event when network is left' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, connected: false, network_name: nil, internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:disconnected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits both disconnected and connected events when network roams (non-nil to non-nil)' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'OldNetwork', internet_state: :reachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'NewNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:disconnected, { network_name: 'OldNetwork' }, kind_of(Hash), kind_of(Hash))
      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'NewNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit disconnect/connect events when only SSID visibility degrades' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'OldNetwork', internet_state: :reachable })

      current_state = {
        wifi_on:        true,
        connected:      true,
        network_name:   '[SSID unavailable]',
        internet_state: :reachable,
      }

      expect(logger).not_to receive(:emit_event).with(:disconnected, anything, anything, anything)
      expect(logger).not_to receive(:emit_event).with(:connected, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_on event when internet becomes available' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :unreachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_off event when internet becomes unavailable' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:internet_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_on event when internet becomes available while WiFi is off' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable })

      current_state =
        { wifi_on: false, connected: false, network_name: nil, internet_state: :reachable }

      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_off event when internet becomes unavailable while WiFi is off' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, connected: false, network_name: nil, internet_state: :reachable })

      current_state =
        { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:internet_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit internet_off when connectivity becomes indeterminate' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :indeterminate }

      expect(logger).not_to receive(:emit_event).with(:internet_off, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit internet_on when connectivity resolves from indeterminate' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :indeterminate })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).not_to receive(:emit_event).with(:internet_on, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit internet_off when connectivity resolves from indeterminate to unreachable' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :indeterminate })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :unreachable }

      expect(logger).not_to receive(:emit_event).with(:internet_off, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits events in order: wifi, network, internet when multiple changes happen' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event).with(:wifi_on, {}, kind_of(Hash), kind_of(Hash)).ordered
      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash)).ordered
      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash)).ordered

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit when state does not change' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state =
        { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end
  end

  describe '#emit_event' do
    let(:logger) do
      described_class.new(
        mock_model,
        out_stream:       out_stream,
        log_file_manager: mock_log_file_manager
      )
    end

    it 'creates event with correct structure' do
      previous_state = { wifi_on: false }
      current_state = { wifi_on: true }

      expect(logger).to receive(:log_event) do |event|
        expect(event).to match(
          type:           :wifi_on,
          timestamp:      kind_of(Time),
          previous_state: previous_state,
          current_state:  current_state,
          details:        {}
        )
      end

      logger.send(:emit_event, :wifi_on, {}, previous_state, current_state)
    end

    it 'includes details in event' do
      previous_state = { network_name: nil }
      current_state = { network_name: 'TestNet' }

      expect(logger).to receive(:log_event) do |event|
        expect(event[:details]).to eq({ network_name: 'TestNet' })
      end

      logger.send(:emit_event, :connected, { network_name: 'TestNet' }, previous_state, current_state)
    end
  end

  describe '#format_event_message' do
    let(:logger) do
      described_class.new(mock_model, out_stream: out_stream)
    end

    it 'formats wifi_on event' do
      event = {
        type:      :wifi_on,
        timestamp: Time.new(2025, 10, 28, 14, 32, 30, 0),
        details:   {},
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} WiFi ON/)
    end

    it 'formats wifi_off event' do
      event = {
        type:      :wifi_off,
        timestamp: Time.new(2025, 10, 28, 14, 32, 31, 0),
        details:   {},
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} WiFi OFF/)
    end

    it 'formats connected event' do
      event = {
        type:      :connected,
        timestamp: Time.new(2025, 10, 28, 14, 32, 32, 0),
        details:   { network_name: 'TestNetwork' },
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Connected to TestNetwork/)
    end

    it 'formats disconnected event' do
      event = {
        type:      :disconnected,
        timestamp: Time.new(2025, 10, 28, 14, 32, 33, 0),
        details:   { network_name: 'TestNetwork' },
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Disconnected from TestNetwork/)
    end

    it 'formats internet_on event' do
      event = {
        type:      :internet_on,
        timestamp: Time.new(2025, 10, 28, 14, 32, 30, 0),
        details:   {},
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Internet available/)
    end

    it 'formats internet_off event' do
      event = {
        type:      :internet_off,
        timestamp: Time.new(2025, 10, 28, 14, 33, 0, 0),
        details:   {},
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Internet unavailable/)
    end

    it 'formats unknown event type gracefully' do
      event = {
        type:      :unknown_type,
        timestamp: Time.new(2025, 10, 28, 14, 34, 0, 0),
        details:   {},
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/UNKNOWN EVENT: unknown_type/)
    end
  end

  describe '#run' do
    def with_fake_monotonic_clock(logger)
      current_time = 0.0
      clock_mutex = Mutex.new

      allow(logger).to receive(:monotonic_now) do
        clock_mutex.synchronize { current_time }
      end

      allow(logger).to receive(:sleep_until) do |deadline|
        clock_mutex.synchronize do
          current_time = deadline if deadline > current_time
        end
      end

      [clock_mutex, -> { clock_mutex.synchronize { current_time } }, ->(duration) {
        clock_mutex.synchronize do
          current_time += duration
        end
      }]
    end

    def stub_fetch_current_state_for_overrun(logger, poll_times, poll_times_mutex, advance_clock)
      allow(logger).to receive(:fetch_current_state) do
        current_poll_number = poll_times_mutex.synchronize do
          poll_times << logger.send(:monotonic_now)
          poll_times.length
        end

        advance_clock.call(0.12) if current_poll_number == 2

        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
        }
      end
    end

    it 'logs startup message' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0)
      call_count = 0
      allow(logger).to receive(:detect_and_emit_events) do
        call_count += 1
        logger.stop if call_count >= 1
      end
      logger.run
      expect(out_stream.string).to match(/Event logging started/)
    end

    it 'logs initial state on startup' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0)
      allow(logger).to receive(:detect_and_emit_events) { logger.stop }
      logger.run
      expect(out_stream.string).to match(/Current state: WiFi/)
    end

    it 'logs stopped message on Ctrl+C' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0)
      allow(logger).to receive(:sleep_until).and_raise(Interrupt)
      logger.run
      expect(out_stream.string).to match(/Event logging stopped/)
    end

    it 'calls detect_and_emit_events each iteration after initial state' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0)
      call_count = 0
      allow(logger).to receive(:detect_and_emit_events) do
        call_count += 1
        logger.stop if call_count >= 2
      end
      logger.run
      expect(call_count).to eq(2)
    end

    it 'keeps the configured polling cadence when polls finish within the interval' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.05)
      poll_times = []
      poll_times_mutex = Mutex.new
      _clock_mutex, _read_clock, _advance_clock = with_fake_monotonic_clock(logger)

      allow(logger).to receive(:fetch_current_state) do
        poll_times_mutex.synchronize do
          poll_times << logger.send(:monotonic_now)
        end

        {
          wifi_on:        true,
          connected:      true,
          network_name:   'TestNetwork',
          internet_state: WifiWand::ConnectivityStates::INTERNET_REACHABLE,
        }
      end

      allow(logger).to receive(:detect_and_emit_events) do
        logger.stop if poll_times_mutex.synchronize { poll_times.length >= 3 }
      end

      logger.run

      poll_intervals = poll_times_mutex.synchronize do
        poll_times.each_cons(2).map { |previous_poll, current_poll| current_poll - previous_poll }
      end

      expect(poll_intervals.length).to eq(2)
      expect(poll_intervals).to all(be_within(0.03).of(0.05))
    end

    it 'starts the next poll immediately after a poll overruns the interval' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.05)
      poll_times = []
      poll_times_mutex = Mutex.new
      _clock_mutex, _read_clock, advance_clock = with_fake_monotonic_clock(logger)

      stub_fetch_current_state_for_overrun(logger, poll_times, poll_times_mutex, advance_clock)

      allow(logger).to receive(:detect_and_emit_events) do
        logger.stop if poll_times_mutex.synchronize { poll_times.length >= 3 }
      end

      logger.run

      second_to_third_interval = poll_times_mutex.synchronize do
        poll_times[2] - poll_times[1]
      end

      expect(second_to_third_interval).to be_within(0.04).of(0.12)
    end

    it 'does not perform repeated catch-up polls after one slow poll' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 0.05)
      poll_times = []
      poll_times_mutex = Mutex.new
      _clock_mutex, _read_clock, advance_clock = with_fake_monotonic_clock(logger)

      stub_fetch_current_state_for_overrun(logger, poll_times, poll_times_mutex, advance_clock)

      allow(logger).to receive(:detect_and_emit_events) do
        logger.stop if poll_times_mutex.synchronize { poll_times.length >= 4 }
      end

      logger.run

      intervals = poll_times_mutex.synchronize do
        poll_times.each_cons(2).map { |previous_poll, current_poll| current_poll - previous_poll }
      end

      expect(intervals.length).to eq(3)
      expect(intervals[1]).to be_within(0.04).of(0.12)
      expect(intervals[2]).to be_within(0.03).of(0.05)
    end

    it 'cleans up log file manager on exit after stop interrupts the wait' do
      logger = described_class.new(
        mock_model,
        out_stream:       out_stream,
        interval:         2,
        log_file_manager: mock_log_file_manager
      )

      first_poll_completed = Queue.new
      sleep_started = Queue.new
      first_poll_recorded = false
      allow(logger).to receive(:fetch_current_state).and_wrap_original do |original, *args|
        result = original.call(*args)
        unless first_poll_recorded
          first_poll_completed << true
          first_poll_recorded = true
        end
        result
      end
      allow(logger).to receive(:sleep_until).and_wrap_original do |original, *args|
        sleep_started << true
        original.call(*args)
      end

      runner = Thread.new { logger.run }
      Timeout.timeout(0.5) { first_poll_completed.pop }
      Timeout.timeout(0.5) { sleep_started.pop }

      logger.stop
      expect(runner.join(0.3)).to eq(runner)
      expect(mock_log_file_manager).to have_received(:close)
    end
  end

  describe '#stop' do
    it 'interrupts the polling wait so the run loop stops promptly' do
      logger = described_class.new(mock_model, out_stream: out_stream, interval: 2)
      first_poll_completed = Queue.new
      sleep_started = Queue.new
      first_poll_recorded = false

      allow(logger).to receive(:fetch_current_state).and_wrap_original do |original, *args|
        result = original.call(*args)
        unless first_poll_recorded
          first_poll_completed << true
          first_poll_recorded = true
        end
        result
      end
      allow(logger).to receive(:sleep_until).and_wrap_original do |original, *args|
        sleep_started << true
        original.call(*args)
      end

      runner = Thread.new { logger.run }
      Timeout.timeout(0.5) { first_poll_completed.pop }
      Timeout.timeout(0.5) { sleep_started.pop }

      stop_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      logger.stop
      expect(runner.join(0.3)).to eq(runner)

      stop_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - stop_started_at

      expect(logger.instance_variable_get(:@running)).to be false
      expect(stop_duration).to be < 0.3
    end
  end

  describe '#log_initial_state' do
    let(:logger) do
      described_class.new(mock_model, out_stream: out_stream)
    end

    it 'logs initial state with all fields available' do
      state = { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi on, connected to TestNetwork, internet available/
        )
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs initial state with WiFi off' do
      state = { wifi_on: false, connected: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi off, not connected, internet unavailable/
        )
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs initial state with indeterminate internet connectivity as unknown' do
      state = { wifi_on: true, connected: true, network_name: 'TestNetwork', internet_state: :indeterminate }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi on, connected to TestNetwork, internet unknown/
        )
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs degraded connected state when the SSID is unavailable' do
      state = { wifi_on: true, connected: true, network_name: nil, internet_state: :reachable }
      expected_pattern = Regexp.new(
        "#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi on, " \
          'connected \(SSID unavailable\), internet available'
      )

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(expected_pattern)
      end

      logger.send(:log_initial_state, state)
    end
  end

  describe '#cleanup' do
    it 'closes log file manager and sets it to nil' do
      logger = described_class.new(
        mock_model,
        out_stream:       out_stream,
        log_file_manager: mock_log_file_manager
      )
      logger.cleanup
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end

    it 'handles nil log file manager gracefully' do
      logger = described_class.new(mock_model, out_stream: out_stream)
      logger.instance_variable_set(:@log_file_manager, nil)
      expect { logger.cleanup }.not_to raise_error
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end
  end

  describe 'log file failures' do
    it 'warns and falls back to stdout when a log file write fails after initialization' do
      logger = described_class.new(
        mock_model,
        out_stream:       out_stream,
        log_file_manager: mock_log_file_manager
      )
      allow(mock_log_file_manager).to receive(:write)
        .and_raise(WifiWand::LogWriteError, 'Failed to write to log file /tmp/test.log: disk full')

      expect { logger.send(:log_message, 'test message') }.not_to raise_error
      expect(out_stream.string).to include('test message')
      expect(out_stream.string).to include(
        'WARNING: File logging is disabled. Stdout is the only remaining log destination.'
      )
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.log_file_manager).to be_nil
    end

    it 'falls back to stdout even when closing the broken log file also fails' do
      logger = described_class.new(
        mock_model,
        out_stream:       out_stream,
        log_file_manager: mock_log_file_manager
      )
      allow(mock_log_file_manager).to receive(:write)
        .and_raise(WifiWand::LogWriteError, 'Failed to write to log file /tmp/test.log: disk full')
      allow(mock_log_file_manager).to receive(:close).and_raise(StandardError, 'close failed')

      expect { logger.send(:log_message, 'test message') }.not_to raise_error
      expect(out_stream.string).to include(
        'WARNING: File logging is disabled. Stdout is the only remaining log destination.'
      )
      expect(out_stream.string).to include('Cleanup also failed: close failed')
      expect(logger.log_file_manager).to be_nil
    end

    it 'raises when a log file write fails and no stdout fallback exists' do
      logger = described_class.new(
        mock_model,
        out_stream:       nil,
        log_file_manager: mock_log_file_manager
      )
      allow(mock_log_file_manager).to receive(:write)
        .and_raise(WifiWand::LogWriteError, 'Failed to write to log file /tmp/test.log: disk full')

      expect do
        logger.send(:log_message, 'test message')
      end.to raise_error(WifiWand::LogWriteError, /disk full/)
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.log_file_manager).to be_nil
    end
  end
end
