# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/command_line_interface'

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

    it 'returns syntax guidance for empty argv without creating a model' do
      err_stream = StringIO.new
      opts = create_cli_options(argv: [], err_stream: err_stream)

      expect(WifiWand).not_to receive(:create_model)

      empty_cli = described_class.new(opts, argv: [])

      expect(empty_cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Syntax is:')
      expect(err_stream.string).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
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
      expect(WifiWand).not_to receive(:create_model)

      cli = described_class.new(opts, argv: ['shell'])

      expect(cli).not_to receive(:run_shell)

      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Output formatting is not supported for the shell command.')
    end

    it 'returns failure when shell startup receives trailing arguments' do
      err_stream = StringIO.new
      opts = create_cli_options
      opts.err_stream = err_stream
      expect(WifiWand).not_to receive(:create_model)

      cli = described_class.new(opts, argv: ['shell', '-o', 'j'])

      expect(cli).not_to receive(:run_shell)

      expect(cli.call).to eq(described_class::FAILURE_EXIT_CODE)
      expect(err_stream.string).to include('Unexpected argument(s): -o, j')
      expect(err_stream.string).to include('Usage: wifi-wand shell')
      expect(err_stream.string).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
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

  describe 'query command exit behavior' do
    def call_cli_command(command_name)
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options(argv: [command_name], out_stream: out_stream, err_stream: err_stream)
      query_cli = described_class.new(opts)

      {
        status: query_cli.call,
        stdout: out_stream.string,
        stderr: err_stream.string,
      }
    end

    it 'prints the project URL through the normal CLI dispatcher' do
      result = call_cli_command('url')

      expect(result[:status]).to eq(described_class::SUCCESS_EXIT_CODE)
      expect(result[:stdout]).to eq("#{WifiWand::PROJECT_URL}\n")
      expect(result[:stderr]).to be_empty
    end

    it 'prints the project URL as valid JSON through the normal CLI dispatcher' do
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options(
        argv:           ['url'],
        out_stream:     out_stream,
        err_stream:     err_stream,
        post_processor: ->(object) { JSON.generate(object) }
      )
      url_cli = described_class.new(opts)

      expect(url_cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
      expect(JSON.parse(out_stream.string)).to eq(WifiWand::PROJECT_URL)
      expect(err_stream.string).to be_empty
    end

    {
      'Location Services denial'    => {
        diagnostic: 'wifiwand helper: Location Services denied. Run `wifi-wand-macos-setup`.',
        scan:       {
          'networks'          => [],
          'scan_status'       => 'location_services_blocked',
          'scan_source'       => 'fallback',
          'ssid_data_trusted' => false,
          'warning'           => 'macOS blocked wifiwand-helper from reading WiFi SSIDs',
        },
      },
      'helper installation failure' => {
        diagnostic: 'wifiwand helper: failed to install helper (boom). Helper disabled until the next run.',
        scan:       {
          'networks'          => ['Cafe'],
          'scan_status'       => 'ok',
          'scan_source'       => 'fallback',
          'ssid_data_trusted' => true,
          'warning'           => nil,
        },
      },
    }.each do |description, data|
      it "keeps avail_nets JSON valid when the macOS helper reports #{description}" do
        out_stream = StringIO.new
        err_stream = StringIO.new
        fake_os = double('mac_os')
        allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(fake_os)
        allow(fake_os).to receive(:create_model) do |model_options|
          double('mac_model').tap do |model|
            allow(model).to receive(:available_network_scan) do
              model_options.fetch(:err_stream).puts(data.fetch(:diagnostic))
              data.fetch(:scan)
            end
          end
        end
        opts = create_cli_options(
          argv:           ['avail_nets'],
          out_stream:     out_stream,
          err_stream:     err_stream,
          post_processor: ->(object) { JSON.generate(object) }
        )
        json_cli = described_class.new(opts)

        expect(json_cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
        expect(JSON.parse(out_stream.string)).to eq(data.fetch(:scan))
        expect(out_stream.string).not_to include('wifiwand helper:')
        expect(err_stream.string).to include(data.fetch(:diagnostic))
      end
    end

    it 'keeps helper diagnostics on stderr for normal text avail_nets output' do
      out_stream = StringIO.new
      err_stream = StringIO.new
      diagnostic = 'wifiwand helper: Location Services denied. Run `wifi-wand-macos-setup`.'
      scan = {
        'networks'          => [],
        'scan_status'       => 'location_services_blocked',
        'scan_source'       => 'fallback',
        'ssid_data_trusted' => false,
        'warning'           => 'macOS blocked wifiwand-helper from reading WiFi SSIDs',
      }
      fake_os = double('mac_os')
      allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(fake_os)
      allow(fake_os).to receive(:create_model) do |model_options|
        double('mac_model').tap do |model|
          allow(model).to receive(:available_network_scan) do
            model_options.fetch(:err_stream).puts(diagnostic)
            scan
          end
        end
      end
      opts = create_cli_options(argv: ['avail_nets'], out_stream: out_stream, err_stream: err_stream)
      text_cli = described_class.new(opts)

      expect(text_cli.call).to eq(described_class::SUCCESS_EXIT_CODE)
      expect(out_stream.string).not_to include('wifiwand helper:')
      expect(out_stream.string).to include('Warning: macOS blocked wifiwand-helper')
      expect(err_stream.string).to include(diagnostic)
    end

    it 'returns failure when avail_nets cannot scan because WiFi is off' do
      allow(mock_model).to receive(:available_network_names)
        .and_raise(WifiWand::WifiOffError.new('WiFi is off, cannot scan for available networks.'))

      result = call_cli_command('avail_nets')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include('WiFi is off, cannot scan for available networks.')
    end

    it 'returns failure when network_name cannot query because WiFi is off' do
      allow(mock_model).to receive(:connected_network_name)
        .and_raise(WifiWand::WifiOffError.new('WiFi is off'))

      result = call_cli_command('network_name')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include('WiFi is off')
    end

    it 'returns failure when macOS redacts the exact network identity' do
      error = WifiWand::MacOsRedactionError.new(operation_description: 'showing the current SSID')
      allow(mock_model).to receive(:connected_network_name).and_raise(error)

      result = call_cli_command('network_name')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include('Exact WiFi network identity is required')
      expect(result[:stderr]).to include('wifi-wand-macos-setup')
    end
  end

  describe 'nameservers command exit behavior' do
    def call_nameservers_command(*args)
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options(
        argv:       ['nameservers', *args],
        out_stream: out_stream,
        err_stream: err_stream
      )
      nameservers_cli = described_class.new(opts)

      {
        cli:    nameservers_cli,
        status: nameservers_cli.call,
        stdout: out_stream.string,
        stderr: err_stream.string,
      }
    end

    it 'returns failure when get receives extra arguments' do
      result = call_nameservers_command('get', '1.1.1.1')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include('Unexpected argument(s): 1.1.1.1')
      expect(result[:stderr]).to include('Usage: wifi-wand nameservers [get|clear|IP ...]')
      expect(result[:stderr]).to include('1.1.1.1')
      expect(result[:stderr]).to include("Use 'wifi-wand help'")
      expect(result[:cli].model).not_to have_received(:nameservers)
    end

    it 'returns failure without clearing DNS when clear receives extra arguments' do
      result = call_nameservers_command('clear', '1.1.1.1')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include('Unexpected argument(s): 1.1.1.1')
      expect(result[:stderr]).to include('Usage: wifi-wand nameservers [get|clear|IP ...]')
      expect(result[:stderr]).to include('1.1.1.1')
      expect(result[:cli].model).not_to have_received(:set_nameservers)
    end
  end

  describe 'ropen command exit behavior' do
    def call_ropen_command(*resource_codes)
      out_stream = StringIO.new
      err_stream = StringIO.new
      opts = create_cli_options(
        argv:       ['ropen', *resource_codes],
        out_stream: out_stream,
        err_stream: err_stream
      )
      ropen_cli = described_class.new(opts)

      allow(ropen_cli.model).to receive(:open_resource)

      {
        cli:    ropen_cli,
        status: ropen_cli.call,
        stdout: out_stream.string,
        stderr: err_stream.string,
      }
    end

    it 'returns failure for an invalid resource code' do
      result = call_ropen_command('bad-code')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include("Invalid resource code: 'bad-code'")
      expect(result[:stderr]).to include('Valid codes are:')
      expect(result[:stderr]).to include("'ipw' (What is My IP)")
    end

    it 'returns failure and opens nothing when valid and invalid codes are mixed' do
      result = call_ropen_command('ipw', 'bad-code')

      expect(result[:status]).to eq(described_class::FAILURE_EXIT_CODE)
      expect(result[:cli].model).not_to have_received(:open_resource)
      expect(result[:stdout]).to be_empty
      expect(result[:stderr]).to include("Invalid resource code: 'bad-code'")
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
