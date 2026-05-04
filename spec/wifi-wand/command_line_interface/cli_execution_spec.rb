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

    it 'dispatches shell through the registered command path' do
      cli = described_class.new(create_cli_options, argv: ['shell'])
      shell_command = instance_double(WifiWand::ShellCommand)

      expect(cli).to receive(:validate_command_line).and_return(described_class::SUCCESS_EXIT_CODE)
      expect(cli).to receive(:resolve_command).with('shell').and_return(shell_command)
      expect(shell_command).to receive(:call)

      expect(cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
    end

    it 'returns failure when shell startup is requested with an output formatter' do
      err_stream = StringIO.new
      opts = create_cli_options(post_processor: ->(object) { object.to_json })
      opts.err_stream = err_stream
      cli = described_class.new(opts, argv: ['shell'])

      expect(cli).not_to receive(:run_shell)

      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Output formatting is not supported for the shell command.')
    end

    it 'returns failure when shell startup receives trailing arguments' do
      err_stream = StringIO.new
      opts = create_cli_options
      opts.err_stream = err_stream
      cli = described_class.new(opts, argv: ['shell', '-o', 'j'])

      expect(cli).not_to receive(:run_shell)

      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('The shell command does not accept arguments.')
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

    it 'prints command error display context in non-verbose mode' do
      error = WifiWand::CommandExecutor::OsCommandError.new(
        exitstatus: 1,
        command:    'nmcli device wifi connect Test',
        text:       'activation failed'
      )
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
      expect(err_stream.string).to include('activation failed')
      expect(err_stream.string).to include('Command failed: nmcli device wifi connect Test')
      expect(err_stream.string).to include('Exit code: 1')
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

  describe 'status command exit behavior' do
    it 'returns failure when status data is unavailable in non-interactive mode' do
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options
      opts.out_stream = out_stream
      opts.err_stream = err_stream
      status_cli = described_class.new(opts, argv: ['status'])

      allow(status_cli.model).to receive(:status_line_data).and_return(nil)

      expect(status_cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(out_stream.string).to eq("WiFi: [status unavailable]\n")
      expect(err_stream.string).to include('WiFi status unavailable')
      expect(err_stream.string).not_to include("Use 'wifi-wand help'")
    end

    it 'prints unavailable status instead of formatted nil when output formatting is enabled' do
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options(post_processor: ->(object) { object.to_json })
      opts.out_stream = out_stream
      opts.err_stream = err_stream
      status_cli = described_class.new(opts, argv: ['status'])

      allow(status_cli.model).to receive(:status_line_data).and_return(nil)

      expect(status_cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(out_stream.string).to eq("WiFi: [status unavailable]\n")
      expect(out_stream.string).not_to include('null')
      expect(err_stream.string).to include('WiFi status unavailable')
      expect(err_stream.string).not_to include("Use 'wifi-wand help'")
    end

    it 'returns success and renders partial status data when worker results are degraded' do
      out_stream = StringIO.new
      opts = create_cli_options
      opts.out_stream = out_stream
      status_cli = described_class.new(opts, argv: ['status'])
      partial_status_data = {
        wifi_on:                       true,
        dns_working:                   nil,
        connected:                     nil,
        internet_state:                :indeterminate,
        internet_check_complete:       true,
        network_name:                  nil,
        captive_portal_state:          :indeterminate,
        captive_portal_login_required: :unknown,
      }

      allow(status_cli.model).to receive(:status_line_data).and_return(partial_status_data)

      expect(status_cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
      expect(out_stream.string).to match(/WiFi.*ON.*WiFi Network.*UNKNOWN.*DNS.*WAIT.*Internet.*UNKNOWN/)
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
