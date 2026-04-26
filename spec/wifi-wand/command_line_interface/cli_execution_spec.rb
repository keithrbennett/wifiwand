# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface do
  include_context 'for command line interface tests'

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
    describe '#verbose?' do
      let(:verbose_options) { create_cli_options(verbose: true) }
      let(:verbose_cli) { described_class.new(verbose_options) }

      context 'when verbose option is true' do
        it 'returns true' do
          expect(verbose_cli.verbose?).to be(true)
        end
      end

      context 'when verbose option is false' do
        it 'returns false' do
          expect(cli.verbose?).to be(false)
        end
      end
    end
  end
end
