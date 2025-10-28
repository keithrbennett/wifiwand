# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/event_logger'
require_relative '../../../lib/wifi-wand/services/log_file_manager'

describe WifiWand::EventLogger do
  let(:mock_model) do
    double('Model',
      status_line_data: {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      }
    )
  end

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
      logger = WifiWand::EventLogger.new(mock_model, log_file_path: '/tmp/test.log', output: output)
      expect(logger.log_file_manager).to be_a(WifiWand::LogFileManager)
    end

    it 'accepts custom LogFileManager' do
      logger = WifiWand::EventLogger.new(mock_model, log_file_manager: mock_log_file_manager)
      expect(logger.log_file_manager).to eq(mock_log_file_manager)
    end
  end

  describe '#fetch_current_state' do
    it 'fetches status from model' do
      logger = WifiWand::EventLogger.new(mock_model, output: output)
      state = logger.send(:fetch_current_state)
      expect(state).to eq(mock_model.status_line_data)
    end

    it 'returns nil when model raises error' do
      allow(mock_model).to receive(:status_line_data).and_raise(StandardError, 'Test error')
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
      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      }
      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_off event when wifi turns off' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      })

      current_state = {
        wifi_on: false,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: true  # Internet still connected
      }

      expect(logger).to receive(:emit_event).with(
        :wifi_off,
        {},
        kind_of(Hash),
        kind_of(Hash)
      )

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits wifi_on event when wifi turns on' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: false,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      })

      current_state = {
        wifi_on: true,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:emit_event).with(:wifi_on, {}, kind_of(Hash), kind_of(Hash))
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits connected event when network changes from nil to a network' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      })

      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:emit_event).with(
        :connected,
        { network_name: 'HomeNetwork' },
        kind_of(Hash),
        kind_of(Hash)
      )

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits disconnected event when network becomes nil' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      })

      current_state = {
        wifi_on: true,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:emit_event).with(
        :disconnected,
        { network_name: 'HomeNetwork' },
        kind_of(Hash),
        kind_of(Hash)
      )

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'ignores pending network names' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: :pending,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      })

      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      # Should not emit connected event because previous state was pending
      expect(logger).not_to receive(:emit_event)
      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_on event when internet becomes available' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      })

      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      }

      expect(logger).to receive(:emit_event).with(
        :internet_on,
        {},
        kind_of(Hash),
        kind_of(Hash)
      )

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'emits internet_off event when internet becomes unavailable' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      })

      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:emit_event).with(
        :internet_off,
        {},
        kind_of(Hash),
        kind_of(Hash)
      )

      logger.send(:detect_and_emit_events, current_state)
    end

    it 'does not emit when internet state does not change' do
      logger.instance_variable_set(:@previous_state, {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      })

      current_state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      }

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

      logger.send(:emit_event, :connected, { network_name: 'TestNet' }, previous_state, current_state)
    end
  end

  describe '#format_event_message' do
    let(:logger) do
      WifiWand::EventLogger.new(mock_model, output: output)
    end

    it 'formats wifi_on event' do
      event = {
        type: :wifi_on,
        timestamp: Time.new(2025, 10, 28, 14, 30, 45),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:30:45\] WiFi ON/)
    end

    it 'formats wifi_off event' do
      event = {
        type: :wifi_off,
        timestamp: Time.new(2025, 10, 28, 14, 31, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:31:00\] WiFi OFF/)
    end

    it 'formats connected event with network name' do
      event = {
        type: :connected,
        timestamp: Time.new(2025, 10, 28, 14, 31, 15),
        details: { network_name: 'MyNetwork' }
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:31:15\] Connected to MyNetwork/)
    end

    it 'formats disconnected event with network name' do
      event = {
        type: :disconnected,
        timestamp: Time.new(2025, 10, 28, 14, 32, 0),
        details: { network_name: 'MyNetwork' }
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:32:00\] Disconnected from MyNetwork/)
    end

    it 'formats internet_on event' do
      event = {
        type: :internet_on,
        timestamp: Time.new(2025, 10, 28, 14, 32, 30),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:32:30\] Internet available/)
    end

    it 'formats internet_off event' do
      event = {
        type: :internet_off,
        timestamp: Time.new(2025, 10, 28, 14, 33, 0),
        details: {}
      }
      message = logger.send(:format_event_message, event)
      expect(message).to match(/\[2025-10-28 14:33:00\] Internet unavailable/)
    end
  end

  describe '#log_initial_state' do
    let(:logger) do
      WifiWand::EventLogger.new(mock_model, output: output)
    end

    it 'logs initial state with all components and timestamp' do
      state = {
        wifi_on: true,
        network_name: 'HomeNetwork',
        tcp_working: true,
        dns_working: true,
        internet_connected: true
      }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Current state: WiFi ON, connected to "HomeNetwork", internet available/)
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs WiFi off state with timestamp' do
      state = {
        wifi_on: false,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Current state: WiFi OFF/)
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs WiFi on without internet with timestamp' do
      state = {
        wifi_on: true,
        network_name: 'TestNet',
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Current state: WiFi ON, connected to "TestNet"/)
      end

      logger.send(:log_initial_state, state)
    end

    it 'logs WiFi on without network with timestamp' do
      state = {
        wifi_on: true,
        network_name: nil,
        tcp_working: false,
        dns_working: false,
        internet_connected: false
      }

      expect(logger).to receive(:log_message) do |message|
        expect(message).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Current state: WiFi ON/)
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
end
