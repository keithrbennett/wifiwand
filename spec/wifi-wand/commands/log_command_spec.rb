# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/log_command'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::LogCommand do
  let(:mock_model) do
    double('Model',
      status_line_data: {
        wifi_on:                 true,
        network_name:            'HomeNetwork',
        internet_state:          :reachable,
        internet_check_complete: true,
      }
    )
  end

  let(:output) { StringIO.new }

  let(:cli) { double('cli', model: mock_model, verbose_mode: true, out_stream: output) }

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output: :output, verbose: -> { cli.verbose_mode } }


  describe 'initialization' do
    it 'creates an instance with model and output' do
      command = described_class.new(mock_model, output: output)
      expect(command.model).to eq(mock_model)
      expect(command.output).to eq(output)
    end

    it 'defaults verbose to false' do
      command = described_class.new(mock_model)
      expect(command.verbose).to be false
    end

    it 'accepts verbose flag' do
      command = described_class.new(mock_model, verbose: true)
      expect(command.verbose).to be true
    end
  end

  describe '#call' do
    let(:mock_logger) { double('EventLogger', run: nil) }

    before do
      allow(WifiWand::EventLogger).to receive(:new).and_return(mock_logger)
    end

    it 'creates EventLogger with default options (stdout only)' do
      command = described_class.new(mock_model, output: output)
      command.call

      expect(WifiWand::EventLogger).to have_received(:new).with(
        mock_model,
        hash_including(
          interval:      WifiWand::TimingConstants::EVENT_LOG_POLLING_INTERVAL,
          verbose:       false,
          log_file_path: nil,
          output:        output
        )
      )
    end

    it 'runs the logger' do
      command = described_class.new(mock_model, output: output)
      command.call

      expect(mock_logger).to have_received(:run)
    end

    it 'prints help for the log command' do
      command = described_class.new(mock_model, output: output)

      command.call('--help')

      expect(output.string).to include('Usage: wifi-wand log')
      expect(output.string).to include('Options:')
      expect(output.string).to include('--interval N')
      expect(mock_logger).not_to have_received(:run)
    end

    context 'with --interval option' do
      it 'passes custom interval to EventLogger' do
        command = described_class.new(mock_model, output: output)
        command.call('--interval', '10')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 10.0)
        )
      end

      it 'converts interval to float' do
        command = described_class.new(mock_model, output: output)
        command.call('--interval', '2.5')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 2.5)
        )
      end

      it 'raises error for invalid interval value' do
        command = described_class.new(mock_model, output: output)
        expect do
          command.call('--interval', 'invalid')
        end.to raise_error(WifiWand::ConfigurationError)
      end

      it 'raises error for zero interval' do
        command = described_class.new(mock_model, output: output)
        expect do
          command.call('--interval', '0')
        end.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end

      it 'raises error for negative interval' do
        command = described_class.new(mock_model, output: output)
        expect do
          command.call('--interval', '-5')
        end.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end
    end

    context 'with --file option' do
      it 'passes custom log file path and disables stdout' do
        command = described_class.new(mock_model, output: output)
        command.call('--file', '/tmp/custom.log')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(log_file_path: '/tmp/custom.log', output: nil)
        )
      end

      it 'uses default log file name when --file has no argument' do
        command = described_class.new(mock_model, output: output)
        command.call('--file')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: WifiWand::LogFileManager::DEFAULT_LOG_FILE,
            output:        nil
          )
        )
      end

      it 'fails fast when the requested log file cannot be opened and stdout is disabled' do
        command = described_class.new(mock_model, output: output)
        allow(WifiWand::EventLogger).to receive(:new)
          .and_raise(
            WifiWand::LogFileInitializationError,
            'Cannot open log file /missing/events.log: No such file or directory'
          )

        expect do
          command.call('--file', '/missing/events.log')
        end.to raise_error(WifiWand::ConfigurationError, /Cannot open log file \/missing\/events.log/)
      end
    end

    context 'with --stdout option' do
      it 'enables stdout output (default behavior)' do
        command = described_class.new(mock_model, output: output)
        command.call('--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(output: output)
        )
      end

      it 'keeps stdout when explicitly combined with --file' do
        command = described_class.new(mock_model, output: output)
        command.call('--file', '/tmp/test.log', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: '/tmp/test.log',
            output:        output
          )
        )
      end

      it 'falls back to stdout with a warning when file setup fails' do
        command = described_class.new(mock_model, output: output)
        allow(WifiWand::EventLogger).to receive(:new)
          .with(mock_model, hash_including(log_file_path: '/missing/events.log', output: output))
          .and_raise(WifiWand::LogFileInitializationError,
            'Cannot open log file /missing/events.log: No such file or directory')
        allow(WifiWand::EventLogger).to receive(:new)
          .with(
            mock_model,
            interval: WifiWand::TimingConstants::EVENT_LOG_POLLING_INTERVAL,
            verbose:  false,
            output:   output
          )
          .and_return(mock_logger)

        command.call('--file', '/missing/events.log', '--stdout')

        expect(output.string).to include(
  'WARNING: File logging is disabled. Stdout is the only remaining log destination.'
)
        expect(mock_logger).to have_received(:run)
      end
    end

    context 'with --verbose option' do
      it 'passes true to EventLogger when --verbose is specified' do
        command = described_class.new(mock_model, verbose: false, output: output)
        command.call('--verbose')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: true)
        )
      end

      it 'passes true to EventLogger when -v is specified' do
        command = described_class.new(mock_model, verbose: false, output: output)
        command.call('-v')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: true)
        )
      end
    end

    context 'with multiple options' do
      it 'combines --interval and --file correctly (file only)' do
        command = described_class.new(mock_model, verbose: true, output: output)
        command.call('--interval', '3', '--file', '/tmp/test.log')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval:      3.0,
            verbose:       true,
            log_file_path: '/tmp/test.log',
            output:        nil
          )
        )
      end

      it 'combines --interval, --file, and --stdout correctly' do
        command = described_class.new(mock_model, verbose: true, output: output)
        command.call('--interval', '3', '--file', '/tmp/test.log', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval:      3.0,
            verbose:       true,
            log_file_path: '/tmp/test.log',
            output:        output
          )
        )
      end
    end

    it 'raises error for unknown option' do
      command = described_class.new(mock_model, output: output)
      expect do
        command.call('--unknown')
      end.to raise_error(WifiWand::ConfigurationError, /invalid option/)
    end
  end
end
