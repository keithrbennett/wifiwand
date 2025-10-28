# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/log_command'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::LogCommand do
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

  describe 'initialization' do
    it 'creates an instance with model and output' do
      command = WifiWand::LogCommand.new(mock_model, output: output)
      expect(command.model).to eq(mock_model)
      expect(command.output).to eq(output)
    end

    it 'defaults verbose to false' do
      command = WifiWand::LogCommand.new(mock_model)
      expect(command.verbose).to be false
    end

    it 'accepts verbose flag' do
      command = WifiWand::LogCommand.new(mock_model, verbose: true)
      expect(command.verbose).to be true
    end
  end

  describe '#execute' do
    let(:mock_logger) { double('EventLogger', run: nil) }

    before do
      allow(WifiWand::EventLogger).to receive(:new).and_return(mock_logger)
    end

    it 'creates EventLogger with default options (stdout only)' do
      command = WifiWand::LogCommand.new(mock_model, output: output)
      command.execute

      expect(WifiWand::EventLogger).to have_received(:new).with(
        mock_model,
        hash_including(
          interval: WifiWand::TimingConstants::EVENT_LOG_POLLING_INTERVAL,
          verbose: false,
          hook_filespec: nil,
          log_file_path: nil,
          output: output
        )
      )
    end

    it 'runs the logger' do
      command = WifiWand::LogCommand.new(mock_model, output: output)
      command.execute

      expect(mock_logger).to have_received(:run)
    end

    context 'with --interval option' do
      it 'passes custom interval to EventLogger' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--interval', '10')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 10.0)
        )
      end

      it 'converts interval to float' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--interval', '2.5')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 2.5)
        )
      end

      it 'raises error for invalid interval value' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        expect {
          command.execute('--interval', 'invalid')
        }.to raise_error(WifiWand::ConfigurationError)
      end

      it 'raises error for zero interval' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        expect {
          command.execute('--interval', '0')
        }.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end

      it 'raises error for negative interval' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        expect {
          command.execute('--interval', '-5')
        }.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end
    end

    context 'with --file option' do
      it 'passes custom log file path and disables stdout' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--file', '/tmp/custom.log')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(log_file_path: '/tmp/custom.log', output: nil)
        )
      end

      it 'uses default log file name when --file has no argument' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--file')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: WifiWand::LogFileManager::DEFAULT_LOG_FILE,
            output: nil
          )
        )
      end
    end

    context 'with --stdout option' do
      it 'enables stdout output (default behavior)' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(output: output)
        )
      end

      it 'makes stdout additive when combined with --file' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--file', '/tmp/test.log', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: '/tmp/test.log',
            output: output
          )
        )
      end
    end

    context 'with --hook option' do
      it 'passes custom hook filespec to EventLogger' do
        command = WifiWand::LogCommand.new(mock_model, output: output)
        command.execute('--hook', '/custom/hook')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(hook_filespec: '/custom/hook')
        )
      end
    end

    context 'with --verbose option' do
      it 'passes verbose flag to EventLogger' do
        command = WifiWand::LogCommand.new(mock_model, verbose: true, output: output)
        command.execute('--verbose')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: true)
        )
      end
    end

    context 'with multiple options' do
      it 'combines --interval, --file, and --hook correctly (file only)' do
        command = WifiWand::LogCommand.new(mock_model, verbose: true, output: output)
        command.execute('--interval', '3', '--file', '/tmp/test.log', '--hook', '/my/hook')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval: 3.0,
            verbose: true,
            hook_filespec: '/my/hook',
            log_file_path: '/tmp/test.log',
            output: nil
          )
        )
      end

      it 'combines --interval, --file, --hook, and --stdout correctly' do
        command = WifiWand::LogCommand.new(mock_model, verbose: true, output: output)
        command.execute('--interval', '3', '--file', '/tmp/test.log', '--hook', '/my/hook', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval: 3.0,
            verbose: true,
            hook_filespec: '/my/hook',
            log_file_path: '/tmp/test.log',
            output: output
          )
        )
      end
    end

    it 'raises error for unknown option' do
      command = WifiWand::LogCommand.new(mock_model, output: output)
      expect {
        command.execute('--unknown')
      }.to raise_error(WifiWand::ConfigurationError, /invalid option/)
    end
  end
end
