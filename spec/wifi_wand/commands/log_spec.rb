# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/log'
require_relative '../../../lib/wifi_wand/timing_constants'

describe WifiWand::Commands::Log do
  let(:mock_model) do
    double('Model',
      status_line_data: {
        wifi_on:                 true,
        network_name:            'HomeNetwork',
        internet_state:          :reachable,
        internet_check_complete: true,
      },
      runtime_config:   runtime_config
    )
  end

  let(:output) { StringIO.new }
  let(:runtime_config) { WifiWand::RuntimeConfig.new(utc: false, out_stream: output) }

  let(:cli) { double('cli', model: mock_model, verbose?: true, out_stream: output, command_options: {}) }

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output: :output, verbose?: -> { cli.verbose? } }


  describe 'initialization' do
    it 'creates a bound instance with model and output' do
      command = described_class.new.bind(cli)
      expect(command.model).to eq(mock_model)
      expect(command.output).to eq(output)
    end

    it 'binds verbose from the cli' do
      command = described_class.new.bind(cli)
      expect(command.verbose?).to be true
    end

    it 'still allows direct keyword construction when needed' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)
      expect(command.model).to eq(mock_model)
      expect(command.output).to eq(output)
      expect(command.verbose?).to be false
    end
  end

  describe '#call' do
    let(:mock_logger) { double('EventLogger', run: nil) }

    before do
      allow(WifiWand::EventLogger).to receive(:new).and_return(mock_logger)
    end

    it 'raises clearly when a bound cli does not provide command options' do
      bad_cli = double('cli', model: mock_model, verbose?: false, out_stream: output, command_options: nil)
      command = described_class.new.bind(bad_cli)

      expect do
        command.call
      end.to raise_error(
        WifiWand::ConfigurationError,
        /Internal command binding error: log command_options was nil/
      )
    end

    it 'creates EventLogger with default options (stdout only)' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)
      command.call

      expect(WifiWand::EventLogger).to have_received(:new).with(
        mock_model,
        hash_including(
          interval:      WifiWand::TimingConstants::EVENT_LOG_POLLING_INTERVAL,
          verbose:       false,
          log_file_path: nil,
          out_stream:    output
        )
      )
    end

    it 'lets EventLogger inherit the model runtime config' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)

      command.call

      expect(WifiWand::EventLogger).to have_received(:new).with(
        mock_model,
        hash_including(runtime_config: runtime_config)
      )
      expect(WifiWand::EventLogger).to have_received(:new).with(
        mock_model,
        hash_not_including(:utc)
      )
    end

    it 'runs the logger' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)
      command.call

      expect(mock_logger).to have_received(:run)
    end

    context 'when global verbose is enabled on the model' do
      let(:runtime_config) { WifiWand::RuntimeConfig.new(utc: false, out_stream: output, verbose: true) }

      it 'raises ConfigurationError explaining the incompatibility' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)

        expect { command.call }.to raise_error(WifiWand::ConfigurationError) do |error|
          expect(error.message).to include(
            'Global --verbose is incompatible with the log command',
            'without global verbose',
            '--verbose-logs true'
          )
        end
        expect(mock_logger).not_to have_received(:run)
      end

      it 'does not raise when --help is requested despite global verbose being on' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)

        expect { command.call('--help') }.not_to raise_error
        expect(output.string).to include('Usage: wifiwand log')
        expect(output.string).to include('Options:')
        expect(mock_logger).not_to have_received(:run)
      end

      it 'does not raise when -h is requested despite global verbose being on' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)

        expect { command.call('-h') }.not_to raise_error
        expect(output.string).to include('Usage: wifiwand log')
        expect(mock_logger).not_to have_received(:run)
      end
    end

    it 'prints help for the log command' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)

      command.call('--help')

      expect(output.string).to include('Usage: wifiwand log')
      expect(output.string).to include('Options:')
      expect(output.string).to include('--interval N')
      expect(mock_logger).not_to have_received(:run)
    end

    context 'with --interval option' do
      it 'passes custom interval to EventLogger' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--interval', '10')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 10.0)
        )
      end

      it 'converts interval to float' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--interval', '2.5')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 2.5)
        )
      end

      it 'uses interval parsed by the top-level command parser' do
        command = described_class.new(
          model:           mock_model,
          output:          output,
          verbose_flag:    false,
          command_options: { interval: 4.0 }
        )
        command.call

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(interval: 4.0)
        )
      end

      it 'validates interval parsed by the top-level command parser' do
        command = described_class.new(
          model:           mock_model,
          output:          output,
          verbose_flag:    false,
          command_options: { interval: 0.0 }
        )

        expect { command.call }
          .to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end

      it 'raises error for invalid interval value' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        expect do
          command.call('--interval', 'invalid')
        end.to raise_error(WifiWand::ConfigurationError)
      end

      it 'raises error for zero interval' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        expect do
          command.call('--interval', '0')
        end.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end

      it 'raises error for negative interval' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        expect do
          command.call('--interval', '-5')
        end.to raise_error(WifiWand::ConfigurationError, /Interval must be greater than 0/)
      end
    end

    context 'with --file option' do
      it 'passes custom log file path and disables stdout' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--file', '/tmp/custom.log')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(log_file_path: '/tmp/custom.log', out_stream: nil)
        )
      end

      it 'uses default log file name when --file has no argument' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--file')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: WifiWand::LogFileManager::DEFAULT_LOG_FILE,
            out_stream:    nil
          )
        )
      end

      it 'uses file destination parsed by the top-level command parser' do
        command = described_class.new(
          model:           mock_model,
          output:          output,
          verbose_flag:    false,
          command_options: {
            file_destination_requested: true,
            log_file_path:              '/tmp/preparsed.log',
          }
        )
        command.call

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(log_file_path: '/tmp/preparsed.log', out_stream: nil)
        )
      end

      it 'fails fast when the requested log file cannot be opened and stdout is disabled' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
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
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(out_stream: output)
        )
      end

      it 'keeps stdout when explicitly combined with --file' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        command.call('--file', '/tmp/test.log', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            log_file_path: '/tmp/test.log',
            out_stream:    output
          )
        )
      end

      it 'falls back to stdout with a warning when file setup fails' do
        command = described_class.new(model: mock_model, output: output, verbose_flag: false)
        allow(WifiWand::EventLogger).to receive(:new) do |model_arg, **kwargs|
          expect(model_arg).to eq(mock_model)

          if kwargs[:log_file_path] == '/missing/events.log'
            raise(
              WifiWand::LogFileInitializationError,
              'Cannot open log file /missing/events.log: No such file or directory'
            )
          end

          expect(kwargs).to include(
            interval:   WifiWand::TimingConstants::EVENT_LOG_POLLING_INTERVAL,
            verbose:    false,
            out_stream: output
          )
          mock_logger
        end

        command.call('--file', '/missing/events.log', '--stdout')

        expect(output.string).to include(
          'File logging is disabled. Stdout is the only remaining log destination.'
        )
        expect(output.string).to include('"event":"warning"')
        expect(output.string).to match(
          /"timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})"/
        )
        expect(mock_logger).to have_received(:run)
      end

      it 'uses UTC timestamps in the fallback warning when the model runtime config requests UTC' do
        utc_model = double('Model',
          status_line_data: {
            wifi_on:                 true,
            network_name:            'HomeNetwork',
            internet_state:          :reachable,
            internet_check_complete: true,
          },
          runtime_config:   WifiWand::RuntimeConfig.new(utc: true, out_stream: output))
        command = described_class.new(model: utc_model, output: output, verbose_flag: false)
        allow(WifiWand::EventLogger).to receive(:new) do |_model_arg, **kwargs|
          if kwargs[:log_file_path] == '/missing/events.log'
            raise(
              WifiWand::LogFileInitializationError,
              'Cannot open log file /missing/events.log: No such file or directory'
            )
          end

          mock_logger
        end

        command.call('--file', '/missing/events.log', '--stdout')

        expect(output.string).to match(/"timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"/)
      end
    end

    context 'with --verbose-logs option' do
      it 'passes true to EventLogger when --verbose-logs true is specified' do
        command = described_class.new(model: mock_model, verbose_flag: false, output: output)
        command.call('--verbose-logs', 'true')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: true)
        )
      end

      it 'passes true to EventLogger when --verbose-logs=true is specified' do
        command = described_class.new(model: mock_model, verbose_flag: false, output: output)
        command.call('--verbose-logs=true')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: true)
        )
      end

      it 'passes false to EventLogger when --verbose-logs false is specified' do
        command = described_class.new(model: mock_model, verbose_flag: true, output: output)
        command.call('--verbose-logs', 'false')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(verbose: false)
        )
      end

      it 'raises a configuration error when --verbose-logs has no value' do
        command = described_class.new(model: mock_model, verbose_flag: false, output: output)

        expect do
          command.call('--verbose-logs')
        end.to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('missing argument: --verbose-logs')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
      end
    end

    context 'with multiple options' do
      it 'combines --interval and --file correctly (file only)' do
        command = described_class.new(model: mock_model, verbose_flag: true, output: output)
        command.call('--interval', '3', '--file', '/tmp/test.log')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval:      3.0,
            verbose:       true,
            log_file_path: '/tmp/test.log',
            out_stream:    nil
          )
        )
      end

      it 'combines --interval, --file, and --stdout correctly' do
        command = described_class.new(model: mock_model, verbose_flag: true, output: output)
        command.call('--interval', '3', '--file', '/tmp/test.log', '--stdout')

        expect(WifiWand::EventLogger).to have_received(:new).with(
          mock_model,
          hash_including(
            interval:      3.0,
            verbose:       true,
            log_file_path: '/tmp/test.log',
            out_stream:    output
          )
        )
      end
    end

    it 'raises error for unexpected positional arguments before building the logger' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)

      expect do
        command.call('--interval', '2', 'ignored')
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Unexpected argument(s): ignored')
        expect(error.message).to include('Usage: wifiwand log')
      }
      expect(WifiWand::EventLogger).not_to have_received(:new)
      expect(mock_logger).not_to have_received(:run)
    end

    it 'raises error for unknown option' do
      command = described_class.new(model: mock_model, output: output, verbose_flag: false)
      expect do
        command.call('--unknown')
      end.to raise_error(WifiWand::ConfigurationError, /invalid option/)
    end
  end
end
