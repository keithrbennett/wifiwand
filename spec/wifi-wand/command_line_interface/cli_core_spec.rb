# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface do
  include_context 'for command line interface tests'

  describe 'initialization' do
    it 'raises NoSupportedOSError when no OS is detected' do
      allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(nil)

      expect { described_class.new(options) }.to raise_error(WifiWand::NoSupportedOSError)
    end

    it 'sets interactive mode correctly' do
      options.interactive_mode = true
      cli = described_class.new(options)
      expect(cli.interactive_mode).to be(true)
    end

    it 'does not start the shell from the constructor in interactive mode' do
      interactive_options = create_cli_options(interactive_mode: true)
      interactive_cli = described_class.new(interactive_options)
      expect(interactive_cli).not_to receive(:run_shell)
    end

    it 'uses WifiWand.create_model to build the model with derived options' do
      expect(WifiWand).to receive(:create_model) do |model_options|
        expect(model_options).to be_a(Hash)
        expect(model_options[:verbose]).to eq(options.verbose)
        expect(model_options[:wifi_interface]).to eq(options.wifi_interface)
        mock_model
      end

      cli = described_class.new(options)
      expect(cli.model).to eq(mock_model)
    end
  end

  describe 'command validation' do
    before do
      allow(cli).to receive(:print_help)
    end

    describe '#validate_command_line' do
      specify 'validation returns error when no command is provided' do
        err_stream = StringIO.new
        opts = options.dup
        opts.err_stream = err_stream
        cli = described_class.new(opts, argv: [])
        expect(cli.validate_command_line).to eq(described_class::FAILURE_EXIT_CODE)
        expect(err_stream.string).to match(/Syntax is:/)
      end

      specify 'validation succeeds when command is provided' do
        cli = described_class.new(options, argv: ['info'])
        expect(cli.validate_command_line).to eq(described_class::SUCCESS_EXIT_CODE)
      end
    end
  end

  describe 'command registry and routing' do
    describe 'CommandRegistry module' do
      it 'defines expected commands' do
        commands = cli.commands
        expect(commands).to be_an(Array)

        command_strings = commands.map { |command| command.metadata.long_string }
        expect(command_strings).to include('info', 'connect', 'disconnect', 'help', 'avail_nets')
      end

      specify 'exact short and long command names are accepted' do
        expect(cli.find_command_action('co')).to respond_to(:call)
        expect(cli.find_command_action('connect')).to respond_to(:call)
      end

      specify 'intermediate partial command names are rejected' do
        expect(cli.find_command_action('con')).to be_nil
        expect(cli.find_command_action('conn')).to be_nil
        expect(cli.find_command_action('connec')).to be_nil
      end

      specify 'invalid command strings will return nil' do
        expect(cli.find_command_action('unknown_command')).to be_nil
      end

      specify 'short names still work while invalid short partials do not' do
        expect(cli.find_command_action('c')).to be_nil
        expect(cli.find_command_action('co')).to respond_to(:call)
      end
    end

    describe '#attempt_command_action' do
      it 'executes valid commands' do
        output_support = double('output_support')
        allow(cli).to receive(:output_support).and_return(output_support)
        info_command = WifiWand::InfoCommand.new.bind(cli)
        allow(cli).to receive(:resolve_command).with('info').and_return(info_command)
        allow(mock_model).to receive(:wifi_info).and_return('info_result')
        allow(output_support).to receive(:format_object).with('info_result').and_return('info_result')
        allow(output_support).to receive(:handle_output).and_return('info_result')

        result = cli.attempt_command_action('info')
        expect(result).to eq('info_result')
      end

      it 'calls error handler for invalid commands' do
        error_handler_called = false
        error_handler = -> { error_handler_called = true }

        result = cli.attempt_command_action('invalid_command', &error_handler)
        expect(result).to be_nil
        expect(error_handler_called).to be(true)
      end

      it 'passes arguments to command objects' do
        expect(mock_model).to receive(:connect).with('network', 'password')
        allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(false)

        result = cli.attempt_command_action('connect', 'network', 'password')
        expect(result).to be_nil
      end
    end
  end

  describe 'command line processing' do
    describe '#process_command_line' do
      before do
        allow(cli).to receive(:print_help)
      end

      it 'processes valid commands' do
        output_support = double('output_support')
        cli = described_class.new(options, argv: ['info'])
        allow(cli).to receive(:output_support).and_return(output_support)
        info_command = WifiWand::InfoCommand.new.bind(cli)
        allow(cli).to receive(:resolve_command).with('info').and_return(info_command)
        allow(cli.model).to receive(:wifi_info).and_return('info result')
        allow(output_support).to receive(:format_object).with('info result').and_return('info result')
        allow(output_support).to receive(:handle_output).and_return('info result')

        result = cli.process_command_line
        expect(result).to eq('info result')
      end

      it 'raises BadCommandError for invalid commands' do
        cli = described_class.new(options, argv: %w[invalid_command arg1 arg2])

        expect { cli.process_command_line }.to raise_error(WifiWand::BadCommandError) do |error|
          expect(error.message).to include('Unrecognized command')
          expect(error.message).to include('invalid_command')
          expect(error.message).to include('arg1')
          expect(error.message).to include('arg2')
        end
      end

      it 'raises BadCommandError for intermediate partial commands' do
        cli = described_class.new(options, argv: %w[con TestNetwork])

        expect { cli.process_command_line }.to raise_error(WifiWand::BadCommandError) do |error|
          expect(error.message).to include('Unrecognized command')
          expect(error.message).to include('con')
          expect(error.message).to include('TestNetwork')
        end
      end

      it 'passes command arguments correctly' do
        cli = described_class.new(options, argv: %w[connect TestNetwork password123])
        allow(cli.model).to receive(:connect).with('TestNetwork', 'password123')
        allow(cli.model).to receive(:last_connection_used_saved_password?).and_return(false)

        result = cli.process_command_line
        expect(result).to be_nil
      end

      it 'handles commands with no arguments' do
        output_support = double('output_support')
        cli = described_class.new(options, argv: ['info'])
        allow(cli).to receive(:output_support).and_return(output_support)
        info_command = WifiWand::InfoCommand.new.bind(cli)
        allow(cli).to receive(:resolve_command).with('info').and_return(info_command)
        allow(cli.model).to receive(:wifi_info).and_return('info_output')
        allow(output_support).to receive(:format_object).with('info_output').and_return('info_output')
        allow(output_support).to receive(:handle_output).and_return('info_output')

        result = cli.process_command_line
        expect(result).to eq('info_output')
      end
    end
  end
end
