# frozen_string_literal: true

require 'tempfile'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/event_logger'
require_relative '../../../lib/wifi-wand/services/log_file_manager'

describe WifiWand::EventLogger do
  # ISO-8601 timestamp format pattern: [YYYY-MM-DDTHH:MM:SSZ]
  ISO8601_TIMESTAMP_PATTERN = '\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]'

  let(:mock_model) { double('Model', fast_connectivity?: true) }
  let(:output) { StringIO.new }
  let(:mock_log_file_manager) { double('LogFileManager', write: nil, close: nil) }

  describe 'initialization' do
    it 'creates an instance with default values' do
      logger = WifiWand::EventLogger.new(mock_model)
      expect(logger.model).to eq(mock_model)
      expect(logger.interval).to eq(5)
      expect(logger.verbose).to be false
    end

    it 'accepts custom interval' do
      logger = WifiWand::EventLogger.new(mock_model, interval: 10)
      expect(logger.interval).to eq(10)
    end

    it 'accepts verbose flag' do
      logger = WifiWand::EventLogger.new(mock_model, verbose: true)
      expect(logger.verbose).to be true
    end

    it 'accepts custom hook filespec' do
      logger = WifiWand::EventLogger.new(mock_model, hook_filespec: '/custom/hook')
      expect(logger.hook_filespec).to eq('/custom/hook')
    end

    it 'does not create LogFileManager when no file path specified (stdout-only mode)' do
      logger = WifiWand::EventLogger.new(mock_model, output: output)
      expect(logger.log_file_manager).to be_nil
    end

    it 'creates LogFileManager when file path specified' do
      Dir.mktmpdir do |dir|
        log_file_path = File.join(dir, 'test.log')
        logger = WifiWand::EventLogger.new(mock_model, log_file_path: log_file_path, output: output)
        expect(logger.log_file_manager).to be_a(WifiWand::LogFileManager)
        logger.cleanup
      end
    end

    it 'accepts custom LogFileManager' do
      logger = WifiWand::EventLogger.new(mock_model, log_file_manager: mock_log_file_manager)
      expect(logger.log_file_manager).to eq(mock_log_file_manager)
    end

    it 'respects nil output (file-only mode, no stdout)' do
      Dir.mktmpdir do |dir|
        log_file_path = File.join(dir, 'test.log')
        logger = WifiWand::EventLogger.new(
          mock_model,
          log_file_path: log_file_path,
          output: nil,
          log_file_manager: mock_log_file_manager
        )
        expect(logger.output).to be_nil
        # Verify log_message doesn't call puts when output is nil
        expect { logger.send(:log_message, 'test message') }.not_to raise_error
        expect(mock_log_file_manager).to have_received(:write).with('test message')
      end
    end
  end

  describe '#fetch_current_state' do
    it 'fetches connectivity status from model' do
      logger = WifiWand::EventLogger.new(mock_model, output: output)
      state = logger.send(:fetch_current_state)
      expect(state).to eq({ internet_connected: true })
    end

    it 'returns nil when model raises error' do
      allow(mock_model).to receive(:fast_connectivity?).and_raise(StandardError, 'Test error')
      logger = WifiWand::EventLogger.new(mock_model, output: output)
      state = logger.send(:fetch_current_state)
      expect(state).to be_nil
    end
  end

  describe '#detect_and_emit_events' do
    let(:logger) do
      WifiWand::EventLogger.new(
        mock_model,
        output: output,
        log_file_manager: mock_log_file_manager
      )
    end

    it 'does not emit events on first call (no previous state)' do
      current_state = { internet_connected: true }
      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_on event when internet becomes available' do
      logger.instance_variable_set(:@previous_state, { internet_connected: false })

      current_state = { internet_connected: true }

      expect(logger).to receive(:emit_event).with(:internet_on, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_off event when internet becomes unavailable' do
      logger.instance_variable_set(:@previous_state, { internet_connected: true })

      current_state = { internet_connected: false }

      expect(logger).to receive(:emit_event).with(:internet_off, {}, kind_of(Hash), kind_of(Hash))

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit when internet state does not change' do
      logger.instance_variable_set(:@previous_state, { internet_connected: true })

      current_state = { internet_connected: true }

      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end
  end

  describe '#emit_event' do
    let(:logger) do
      WifiWand::EventLogger.new(
        mock_model,
        output: output,
        log_file_manager: mock_log_file_manager
      )
    end

    it 'creates event with correct structure' do
      previous_state = { wifi_on: false }
      current_state = { wifi_on: true }

      expect(logger).to receive(:log_event) do |event|
        expect(event).to match(
          type: :wifi_on,
          timestamp: kind_of(Time),
          previous_state: previous_state,
          current_state: current_state,
          details: {}
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

      logger.send(:emit_event, :connected, { network_name: 'TestNet' }, previous_state,
        current_state)
    end
  end

  describe '#format_event_message' do
    let(:logger) do
      WifiWand::EventLogger.new(mock_model, output: output)
    end

    it 'formats wifi_on event' do
      event = {
        type: :wifi_on,
        timestamp: Time.new(2025, 10, 28, 14, 30, 45, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} WiFi ON/)
    end

    it 'formats wifi_off event' do
      event = {
        type: :wifi_off,
        timestamp: Time.new(2025, 10, 28, 14, 31, 0, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} WiFi OFF/)
    end

    it 'formats connected event with network name' do
      event = {
        type: :connected,
        timestamp: Time.new(2025, 10, 28, 14, 31, 15, 0),
        details: { network_name: 'MyNetwork' }
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Connected to MyNetwork/)
    end

    it 'formats disconnected event with network name' do
      event = {
        type: :disconnected,
        timestamp: Time.new(2025, 10, 28, 14, 32, 0, 0),
        details: { network_name: 'MyNetwork' }
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Disconnected from MyNetwork/)
    end

    it 'formats internet_on event' do
      event = {
        type: :internet_on,
        timestamp: Time.new(2025, 10, 28, 14, 32, 30, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Internet available/)
    end

    it 'formats internet_off event' do
      event = {
        type: :internet_off,
        timestamp: Time.new(2025, 10, 28, 14, 33, 0, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Internet unavailable/)
    end
  end

  describe '#log_initial_state' do
    let(:logger) do
      WifiWand::EventLogger.new(mock_model, output: output)
    end

    it 'logs initial state with internet available and timestamp' do
      state = { internet_connected: true }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Current state: Internet available/)
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs initial state with internet unavailable and timestamp' do
      state = { internet_connected: false }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/#{ISO8601_TIMESTAMP_PATTERN} Current state: Internet unavailable/)
      end

      logger.send(:log_initial_state, state)
    end
  end

  describe '#cleanup' do
    it 'closes log file manager and sets it to nil' do
      logger = WifiWand::EventLogger.new(
        mock_model,
        output: output,
        log_file_manager: mock_log_file_manager
      )
      logger.cleanup
      expect(mock_log_file_manager).to have_received(:close)
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end

    it 'handles nil log file manager gracefully' do
      logger = WifiWand::EventLogger.new(mock_model, output: output)
      logger.instance_variable_set(:@log_file_manager, nil)
      expect { logger.cleanup }.not_to raise_error
      expect(logger.instance_variable_get(:@log_file_manager)).to be_nil
    end
  end

  describe '#hook_exists?' do
    it 'returns false when hook_filespec is nil' do
      logger = WifiWand::EventLogger.new(mock_model, output: output, hook_filespec: nil)
      expect(logger.send(:hook_exists?)).to be false
    end

    it 'returns false when hook file does not exist' do
      logger = WifiWand::EventLogger.new(mock_model, output: output,
        hook_filespec: '/nonexistent/hook')
      expect(logger.send(:hook_exists?)).to be false
    end

    it 'returns false when hook file exists but is not executable' do
      # Create a temporary non-executable file
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o644, temp_file.path)

      logger = WifiWand::EventLogger.new(mock_model, output: output, hook_filespec: temp_file.path)
      expect(logger.send(:hook_exists?)).to be false

      File.unlink(temp_file.path)
    end

    it 'returns true when hook file exists and is executable' do
      # Create a temporary executable file
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o755, temp_file.path)

      logger = WifiWand::EventLogger.new(mock_model, output: output, hook_filespec: temp_file.path)
      expect(logger.send(:hook_exists?)).to be true

      File.unlink(temp_file.path)
    end
  end

  describe '#execute_hook' do
    let(:logger) do
      WifiWand::EventLogger.new(
        mock_model,
        output: output,
        log_file_manager: mock_log_file_manager
      )
    end

    it 'does not attempt execution if hook does not exist' do
      logger.instance_variable_set(:@hook_filespec, '/nonexistent/hook')
      expect(IO).not_to receive(:popen)
      logger.send(:execute_hook, { type: :wifi_on })
    end

    it 'executes hook script with event JSON via stdin' do
      # Create a temporary executable file
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o755, temp_file.path)

      logger.instance_variable_set(:@hook_filespec, temp_file.path)

      event = {
        type: :internet_on,
        timestamp: Time.now,
        details: {},
        previous_state: {},
        current_state: {}
      }

      # Expect IO.popen to be called with the hook path
      allow(IO).to receive(:popen).and_yield(double('io', write: nil, close_write: nil))

      logger.send(:execute_hook, event)

      expect(IO).to have_received(:popen).with([temp_file.path], 'w')

      File.unlink(temp_file.path)
    end

    it 'handles hook execution errors gracefully' do
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o755, temp_file.path)

      logger.instance_variable_set(:@hook_filespec, temp_file.path)
      logger.instance_variable_set(:@verbose, true)

      allow(IO).to receive(:popen).and_raise(StandardError.new('Hook failed'))

      expect(logger).to receive(:log_message).with(/Hook execution error/)

      logger.send(:execute_hook, { type: :wifi_on })

      File.unlink(temp_file.path)
    end

    it 'passes event as JSON to hook' do
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o755, temp_file.path)

      logger.instance_variable_set(:@hook_filespec, temp_file.path)

      event = {
        type: :connected,
        timestamp: Time.now,
        details: { network_name: 'TestNet' },
        previous_state: { network_name: nil },
        current_state: { network_name: 'TestNet' }
      }

      io_double = double('io')
      allow(IO).to receive(:popen).and_yield(io_double)
      expect(io_double).to receive(:write) do |data|
        parsed = JSON.parse(data)
        expect(parsed['type']).to eq('connected')
        expect(parsed['details']['network_name']).to eq('TestNet')
      end
      expect(io_double).to receive(:close_write)

      logger.send(:execute_hook, event)

      File.unlink(temp_file.path)
    end
  end

  describe 'hook execution integration' do
    it 'calls hook when event is emitted' do
      # Create a temporary executable file
      temp_file = Tempfile.new('hook')
      temp_file.close
      File.chmod(0o755, temp_file.path)

      logger = WifiWand::EventLogger.new(
        mock_model,
        output: output,
        hook_filespec: temp_file.path
      )

      io_double = double('io')
      allow(IO).to receive(:popen).and_yield(io_double)
      expect(io_double).to receive(:write)
      expect(io_double).to receive(:close_write)

      logger.send(:emit_event, :wifi_on, {}, {}, {})

      expect(IO).to have_received(:popen)

      File.unlink(temp_file.path)
    end
  end
end
