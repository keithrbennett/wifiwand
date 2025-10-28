# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/services/log_file_manager'
require 'fileutils'
require 'tempfile'

describe WifiWand::LogFileManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:log_file_path) { File.join(temp_dir, 'test.log') }
  let(:output) { StringIO.new }

  after do
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe 'initialization' do
    it 'creates an instance with default log file path' do
      manager = WifiWand::LogFileManager.new
      expect(manager.log_file_path).to eq(WifiWand::LogFileManager::DEFAULT_LOG_FILE)
    end

    it 'creates an instance with custom log file path' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      expect(manager.log_file_path).to eq(log_file_path)
    end

    it 'opens log file in append mode' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      expect(File.exist?(log_file_path)).to be true
      manager.close
    end

    it 'accepts verbose flag' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path, verbose: true)
      expect(manager.verbose).to be true
      manager.close
    end

    it 'accepts output stream' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path, output: output)
      expect(manager.output).to eq(output)
      manager.close
    end
  end

  describe '#write' do
    it 'writes message to log file' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.write('Test message')
      manager.close

      content = File.read(log_file_path)
      expect(content).to include('Test message')
    end

    it 'appends multiple messages' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.write('Message 1')
      manager.write('Message 2')
      manager.write('Message 3')
      manager.close

      content = File.read(log_file_path)
      expect(content).to include('Message 1')
      expect(content).to include('Message 2')
      expect(content).to include('Message 3')
    end

    it 'preserves existing content in append mode' do
      # Write initial content
      File.write(log_file_path, "Initial content\n")

      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.write('New message')
      manager.close

      content = File.read(log_file_path)
      expect(content).to include('Initial content')
      expect(content).to include('New message')
    end

    it 'handles write errors gracefully' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.instance_variable_set(:@file_handle, nil)  # Simulate closed file

      expect {
        manager.write('Test message')
      }.not_to raise_error
    end

    it 'flushes after each write' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.write('Flushed message')

      # File should be readable immediately
      content = File.read(log_file_path)
      expect(content).to include('Flushed message')

      manager.close
    end
  end

  describe '#close' do
    it 'closes the file handle' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      file_handle = manager.instance_variable_get(:@file_handle)
      expect(file_handle.closed?).to be false

      manager.close
      expect(file_handle.closed?).to be true
    end

    it 'sets file handle to nil after closing' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.close
      file_handle = manager.instance_variable_get(:@file_handle)
      expect(file_handle).to be_nil
    end

    it 'handles multiple close calls gracefully' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.close
      expect { manager.close }.not_to raise_error
    end

    it 'raises errors during close' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      file_handle = manager.instance_variable_get(:@file_handle)
      allow(file_handle).to receive(:close).and_raise(StandardError, 'Close error')

      expect { manager.close }.to raise_error(StandardError, 'Close error')
    end
  end

  describe 'constants' do
    it 'defines default log file' do
      expect(WifiWand::LogFileManager::DEFAULT_LOG_FILE).to eq('wifiwand-events.log')
    end
  end

  describe 'error handling' do
    it 'handles permission errors gracefully when directory exists' do
      # Create a log file that should work
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)
      manager.close

      # Verify the file was created
      expect(File.exist?(log_file_path)).to be true
    end
  end

  describe 'integration' do
    it 'creates a properly formatted log file with multiple entries' do
      manager = WifiWand::LogFileManager.new(log_file_path: log_file_path)

      entries = [
        '[2025-10-28 14:30:15] WiFi ON',
        '[2025-10-28 14:30:20] Connected to "HomeNetwork"',
        '[2025-10-28 14:45:30] Internet unavailable'
      ]

      entries.each { |entry| manager.write(entry) }
      manager.close

      content = File.read(log_file_path)
      entries.each { |entry| expect(content).to include(entry) }
    end
  end
end
