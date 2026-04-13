# frozen_string_literal: true

require 'tempfile'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/event_logger'
require_relative '../../../lib/wifi-wand/services/log_file_manager'

describe WifiWand::EventLogger do
  ISO8601_TIMESTAMP_PATTERN = '\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]'

  let(:mock_model) do
    double('Model',
      fast_connectivity?:     true,
      wifi_on?:               true,
      connected_network_name: 'TestNetwork',
      status_line_data:       { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable },
    )
  end
  let(:output) { StringIO.new }
  let(:mock_log_file_manager) { double('LogFileManager', write: nil, close: nil) }

  describe 'initialization' do
    it 'creates an instance with default values' do
      logger = described_class.new(mock_model)
      expect(logger.model).to eq(mock_model)
      expect(logger.interval).to eq(5)
      expect(logger.verbose).to be false
    end

    it 'accepts custom interval' do
      logger = described_class.new(mock_model, interval: 10)
      expect(logger.interval).to eq(10)
    end

    it 'accepts verbose flag' do
      logger = described_class.new(mock_model, verbose: true)
      expect(logger.verbose).to be true
    end

    it 'does not create LogFileManager when no file path specified (stdout-only mode)' do
      logger = described_class.new(mock_model, output: output)
      expect(logger.log_file_manager).to be_nil
    end

    it 'creates LogFileManager when file path specified' do
      Dir.mktmpdir do |dir|
        log_file_path = File.join(dir, 'test.log')
        logger = described_class.new(mock_model, log_file_path: log_file_path, output: output)
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
          output:           nil,
          log_file_manager: mock_log_file_manager,
        )
        expect(logger.output).to be_nil
        # Verify log_message doesn't call puts when output is nil
        expect { logger.send(:log_message, 'test message') }.not_to raise_error
        expect(mock_log_file_manager).to have_received(:write).with('test message')
      end
    end
  end

  describe '#fetch_current_state' do
    it 'fetches state from model using status_line_data' do
      logger = described_class.new(mock_model, output: output)
      state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }
      expect(mock_model).to receive(:status_line_data).and_return(state)

      expect(logger.send(:fetch_current_state)).to eq(state)
    end

    it 'returns nil and logs message when model raises error in verbose mode' do
      allow(mock_model).to receive(:status_line_data).and_raise(StandardError, 'Test error')
      logger = described_class.new(mock_model, output: output, verbose: true)

      expect(logger).to receive(:log_message).with(/Test error/)
      state = logger.send(:fetch_current_state)
      expect(state).to be_nil
    end
  end

  describe '#detect_and_emit_events' do
    let(:logger) do
      described_class.new(
        mock_model,
        output:           output,
        log_file_manager: mock_log_file_manager,
      )
    end

    it 'does not emit events on first call (no previous state)' do
      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }
      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_on event when WiFi is turned on' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, network_name: nil, internet_state: :unreachable })

      current_state = { wifi_on: true, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:wifi_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_off event when WiFi is turned off' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: nil, internet_state: :unreachable })

      current_state = { wifi_on: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:wifi_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits connected event when network is joined' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: nil, internet_state: :reachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits disconnected event when network is left' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, network_name: nil, internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:disconnected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits both disconnected and connected events when network roams (non-nil to non-nil)' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'OldNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, network_name: 'NewNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event)
        .with(:disconnected, { network_name: 'OldNetwork' }, kind_of(Hash), kind_of(Hash))
      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'NewNetwork' }, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_on event when internet becomes available' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :unreachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_off event when internet becomes unavailable' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :unreachable }

      expect(logger).to receive(:emit_event).with(:internet_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit internet_off when connectivity becomes indeterminate' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :indeterminate }

      expect(logger).not_to receive(:emit_event).with(:internet_off, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit internet_on when connectivity resolves from indeterminate' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :indeterminate })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).not_to receive(:emit_event).with(:internet_on, anything, anything, anything)

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits events in order: wifi, network, internet when multiple changes happen' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: false, network_name: nil, internet_state: :unreachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:emit_event).with(:wifi_on, {}, kind_of(Hash), kind_of(Hash)).ordered
      expect(logger).to receive(:emit_event)
        .with(:connected, { network_name: 'TestNetwork' }, kind_of(Hash), kind_of(Hash)).ordered
      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash)).ordered

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit when state does not change' do
      logger.instance_variable_set(:@previous_state,
        { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable })

      current_state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end
  end

  describe '#emit_event' do
    let(:logger) do
      described_class.new(
        mock_model,
        output:           output,
        log_file_manager: mock_log_file_manager,
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
          details:        {},
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
      described_class.new(mock_model, output: output)
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
    it 'logs startup message' do
      logger = described_class.new(mock_model, output: output, interval: 0)
      allow(logger).to receive(:sleep)
      call_count = 0
      allow(logger).to receive(:detect_and_emit_events) do
        call_count += 1
        logger.stop if call_count >= 1
      end
      logger.run
      expect(output.string).to match(/Event logging started/)
    end

    it 'logs initial state on startup' do
      logger = described_class.new(mock_model, output: output, interval: 0)
      allow(logger).to receive(:sleep)
      allow(logger).to receive(:detect_and_emit_events) { logger.stop }
      logger.run
      expect(output.string).to match(/Current state: WiFi/)
    end

    it 'logs stopped message on Ctrl+C' do
      logger = described_class.new(mock_model, output: output, interval: 0)
      allow(logger).to receive(:sleep).and_raise(Interrupt)
      logger.run
      expect(output.string).to match(/Event logging stopped/)
    end

    it 'calls detect_and_emit_events each iteration after initial state' do
      logger = described_class.new(mock_model, output: output, interval: 0)
      allow(logger).to receive(:sleep)
      call_count = 0
      allow(logger).to receive(:detect_and_emit_events) do
        call_count += 1
        logger.stop if call_count >= 2
      end
      # For initial state
      allow(mock_model).to receive(:status_line_data).and_return({ wifi_on: true })

      logger.run
      expect(call_count).to eq(2)
    end

    it 'sleeps for the configured interval between polls' do
      logger = described_class.new(mock_model, output: output, interval: 7)
      sleep_count = 0
      allow(logger).to receive(:sleep) do |duration|
        sleep_count += 1
        logger.stop if sleep_count >= 1
        expect(duration).to eq(7)
      end
      allow(logger).to receive(:detect_and_emit_events)
      logger.run
    end

    it 'cleans up log file manager on exit' do
      logger = described_class.new(
        mock_model,
        output:           output,
        interval:         0,
        log_file_manager: mock_log_file_manager,
      )
      allow(logger).to receive(:sleep).and_raise(Interrupt)
      logger.run
      expect(mock_log_file_manager).to have_received(:close)
    end
  end

  describe '#stop' do
    it 'sets running to false, stopping the run loop' do
      logger = described_class.new(mock_model, output: output, interval: 0)
      allow(logger).to receive(:sleep)
      allow(logger).to receive(:detect_and_emit_events) { logger.stop }
      logger.run
      expect(logger.instance_variable_get(:@running)).to be false
    end
  end

  describe '#log_initial_state' do
    let(:logger) do
      described_class.new(mock_model, output: output)
    end

    it 'logs initial state with all fields available' do
      state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :reachable }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi on, connected to TestNetwork, internet available/,
        )
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs initial state with WiFi off' do
      state = { wifi_on: false, network_name: nil, internet_state: :unreachable }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi off, not connected, internet unavailable/,
        )
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs initial state with indeterminate internet connectivity as unknown' do
      state = { wifi_on: true, network_name: 'TestNetwork', internet_state: :indeterminate }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(
          /#{ISO8601_TIMESTAMP_PATTERN} Current state: WiFi on, connected to TestNetwork, internet unknown/,
        )
      end

      logger.send(:log_initial_state, state)
    end
  end

  describe '#cleanup' do
    it 'closes log file manager and sets it to nil' do
      logger = described_class.new(
        mock_model,
        output:           output,
        log_file_manager: mock_log_file_manager,
      )
      logger.cleanup
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end

    it 'handles nil log file manager gracefully' do
      logger = described_class.new(mock_model, output: output)
      logger.instance_variable_set(:@log_file_manager, nil)
      expect { logger.cleanup }.not_to raise_error
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end
  end

  describe 'log file failures' do
    it 'warns and falls back to stdout when a log file write fails after initialization' do
      logger = described_class.new(
        mock_model,
        output:           output,
        log_file_manager: mock_log_file_manager,
      )
      allow(mock_log_file_manager).to receive(:write)
        .and_raise(WifiWand::LogWriteError, 'Failed to write to log file /tmp/test.log: disk full')

      expect { logger.send(:log_message, 'test message') }.not_to raise_error
      expect(output.string).to include('test message')
      expect(output.string).to include(
        'WARNING: File logging is disabled. Stdout is the only remaining log destination.',
      )
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.log_file_manager).to be_nil
    end

    it 'falls back to stdout even when closing the broken log file also fails' do
      logger = described_class.new(
        mock_model,
        output:           output,
        log_file_manager: mock_log_file_manager,
      )
      allow(mock_log_file_manager).to receive(:write)
        .and_raise(WifiWand::LogWriteError, 'Failed to write to log file /tmp/test.log: disk full')
      allow(mock_log_file_manager).to receive(:close).and_raise(StandardError, 'close failed')

      expect { logger.send(:log_message, 'test message') }.not_to raise_error
      expect(output.string).to include(
        'WARNING: File logging is disabled. Stdout is the only remaining log destination.',
      )
      expect(output.string).to include('Cleanup also failed: close failed')
      expect(logger.log_file_manager).to be_nil
    end

    it 'raises when a log file write fails and no stdout fallback exists' do
      logger = described_class.new(
        mock_model,
        output:           nil,
        log_file_manager: mock_log_file_manager,
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
