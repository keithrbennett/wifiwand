# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface do
  include_context 'for command line interface tests'

  describe 'output handling' do
    describe '#handle_output' do
      let(:test_data) { { key: 'value' } }
      let(:human_readable_producer) { -> { 'Human readable output' } }
      let(:processor) { ->(obj) { obj.to_s.upcase } }
      let(:options_with_processor) { create_cli_options(post_processor: processor) }
      let(:cli_with_processor) { described_class.new(options_with_processor) }

      context 'when in interactive mode' do
        it 'returns data directly without output' do
          result = interactive_cli.send(:handle_output, test_data, human_readable_producer)
          expect(result).to eq(test_data)
        end
      end

      context 'when in non-interactive mode' do
        context 'with post processor' do
          it 'uses post processor and outputs result' do
            output = nil
            expect do
              silence_output do |stdout, _stderr|
                cli_with_processor.send(:handle_output, test_data, human_readable_producer)
                output = stdout.string
              end
            end.not_to raise_error
            expect(output).to eq(%({:KEY=>"VALUE"}\n)).or eq(%({KEY: "VALUE"}\n))
          end
        end

        context 'without post processor' do
          it 'uses human readable producer and outputs result' do
            expect do
              cli.send(:handle_output, test_data, human_readable_producer)
            end.to output("Human readable output\n").to_stdout
          end
        end
      end
    end
  end

  describe '#call (main entry point)' do
    before do
      allow(cli).to receive_messages(
        process_command_line: 'command_result',
        help_hint:            'Type help for usage'
      )
    end

    it 'validates command line and processes commands successfully' do
      expect(cli).to receive(:validate_command_line).and_return(described_class::SUCCESS_EXIT_CODE)
      expect(cli).to receive(:process_command_line)

      expect(cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
    end

    it 'starts the shell from call in interactive mode' do
      cli = described_class.new(create_cli_options(interactive_mode: true))
      expect(cli).to receive(:run_shell).and_return(0)

      expect(cli.call).to eq(0)
    end

    it 'handles BadCommandError with error message and help hint' do
      error = WifiWand::BadCommandError.new('Invalid command')
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive_messages(
        validate_command_line: described_class::SUCCESS_EXIT_CODE,
        help_hint:             'Type help for usage'
      )
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Invalid command')
      expect(err_stream.string).to include('Type help for usage')
    end

    it 'handles ConfigurationError with error message' do
      error = WifiWand::ConfigurationError.new('Missing required argument')
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive_messages(
        validate_command_line: described_class::SUCCESS_EXIT_CODE,
        help_hint:             'Type help for usage'
      )
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Missing required argument')
      expect(err_stream.string).to include('Type help for usage')
    end

    it 'prints verbose error details as YAML when verbose mode is enabled' do
      error = WifiWand::PublicIPLookupError.new(
        message: 'Public IP lookup failed: malformed response',
        url:     'https://api.country.is/',
        body:    '{"ip":"bad"}'
      )
      err_stream = StringIO.new
      opts = create_cli_options(verbose: true)
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive_messages(
        validate_command_line: described_class::SUCCESS_EXIT_CODE,
        help_hint:             'Type help for usage'
      )
      allow(cli).to receive(:process_command_line).and_raise(error)

      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include(":message: 'Public IP lookup failed: malformed response'")
      expect(err_stream.string).to include(':url: https://api.country.is/')
      expect(err_stream.string).to include(%q(:body: '{"ip":"bad"}'))
    end

    it 'does not duplicate help hint when error message already contains it' do
      error_msg = 'Missing required argument. Type help for usage'
      error = WifiWand::ConfigurationError.new(error_msg)
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive_messages(
        validate_command_line: described_class::SUCCESS_EXIT_CODE,
        help_hint:             'Type help for usage'
      )
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      hint_count = err_stream.string.scan('Type help for usage').length
      expect(hint_count).to eq(1)
    end
  end

  describe 'accessor methods' do
    describe '#verbose_mode' do
      let(:verbose_options) { create_cli_options(verbose: true) }
      let(:verbose_cli) { described_class.new(verbose_options) }

      context 'when verbose option is true' do
        it 'returns true' do
          expect(verbose_cli.verbose_mode).to be(true)
        end
      end

      context 'when verbose option is false' do
        it 'returns false' do
          expect(cli.verbose_mode).to be(false)
        end
      end
    end
  end
end
