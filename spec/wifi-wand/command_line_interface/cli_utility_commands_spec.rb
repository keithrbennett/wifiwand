# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'
require_relative '../../../lib/wifi-wand/commands/log_command'

describe WifiWand::CommandLineInterface do
  include_context 'for command line interface tests'

  describe 'utility commands' do
    describe 'help command' do
      it 'calls print_help method when no command is provided' do
        help_command = WifiWand::HelpCommand.new.bind(cli)
        allow(cli).to receive(:resolve_command).with('help').and_return(help_command)
        allow(cli).to receive(:resolve_command).with(nil).and_return(nil)
        expect(cli).to receive(:print_help)

        invoke_help(cli)
      end

      {
        'log'          => WifiWand::LogCommand,
        'avail_nets'   => WifiWand::AvailNetsCommand,
        'ci'           => WifiWand::CiCommand,
        'connect'      => WifiWand::ConnectCommand,
        'cycle'        => WifiWand::CycleCommand,
        'disconnect'   => WifiWand::DisconnectCommand,
        'info'         => WifiWand::InfoCommand,
        'forget'       => WifiWand::ForgetCommand,
        'nameservers'  => WifiWand::NameserversCommand,
        'network_name' => WifiWand::NetworkNameCommand,
        'off'          => WifiWand::OffCommand,
        'on'           => WifiWand::OnCommand,
        'password'     => WifiWand::PasswordCommand,
        'pref_nets'    => WifiWand::PrefNetsCommand,
        'url'          => WifiWand::UrlCommand,
        'wifi_on'      => WifiWand::WifiOnCommand,
        'qr'           => WifiWand::QrCommand,
        'quit'         => WifiWand::QuitCommand,
        'status'       => WifiWand::StatusCommand,
        'till'         => WifiWand::TillCommand,
      }.each do |command_name, command_class|
        it "prints command-specific help for #{command_name}" do
          command = command_class.new.bind(cli)
          allow(cli).to receive(:resolve_command).with(command_name).and_return(command)

          expect { invoke_help(cli, command_name) }
            .to output(/Usage: wifi-wand #{Regexp.escape(command_name)}/).to_stdout
        end
      end

      it 'prints command-specific help for ropen' do
        resource_manager = double(
          'resource_manager',
          available_resources_help: 'Available resources help text'
        )
        allow(WifiWand::Helpers::ResourceManager).to receive(:new).and_return(resource_manager)
        ropen_command = WifiWand::RopenCommand.new.bind(cli)
        allow(cli).to receive(:resolve_command).with('ropen').and_return(ropen_command)

        expect { invoke_help(cli, 'ropen') }.to output(/Usage: wifi-wand ropen/).to_stdout
      end

      it 'falls back to global help for unknown commands' do
        allow(cli).to receive(:resolve_command).with('unknown').and_return(nil)
        expect(cli).to receive(:print_help)

        invoke_help(cli, 'unknown')
      end
    end

    describe 'status command' do
      let(:status_data) do
        {
          wifi_on:                       true,
          network_name:                  'TestNet',
          tcp_working:                   true,
          dns_working:                   true,
          internet_state:                :reachable,
          captive_portal_login_required: :no,
        }
      end

      it 'outputs status line when not empty' do
        allow(mock_model).to receive(:status_line_data).and_return(status_data)
        out_stream = StringIO.new
        opts = options.dup
        opts.out_stream = out_stream
        cli = described_class.new(opts)
        allow(cli.output_support).to receive(:status_line).with(status_data)
          .and_return('WiFi: ON | Network: "TestNet"')
        invoke_command(cli, 'status')
        expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
      end

      it 'outputs nothing when status line is empty' do
        allow(mock_model).to receive(:status_line_data).and_return(status_data)
        out_stream = StringIO.new
        opts = options.dup
        opts.out_stream = out_stream
        cli = described_class.new(opts)
        allow(cli.output_support).to receive(:status_line).with(status_data).and_return('')
        invoke_command(cli, 'status')
        expect(out_stream.string).to eq('')
      end

      it 'returns structured status data for machine-readable output' do
        opts = create_cli_options(post_processor: ->(obj) { obj.to_json })
        cli = described_class.new(opts)
        allow(cli.model).to receive(:status_line_data).and_return(status_data)

        result = nil
        output = silence_output do |stdout, _stderr|
          result = invoke_command(cli, 'status')
          stdout.string
        end

        expect(result).to eq(status_data)
        parsed = JSON.parse(output)
        expect(parsed['captive_portal_login_required']).to eq('no')
        expect(parsed['internet_state']).to eq('reachable')
        expect(output).not_to include('Captive Portal Login Required')
        expect(output).not_to include('⚠️')
      end
    end

    describe 'quit command aliases' do
      before { allow(cli).to receive(:quit) }

      it 'quit calls quit method' do
        expect(cli).to receive(:quit)
        invoke_command(cli, 'quit')
      end

      it 'xit calls quit method' do
        expect(cli).to receive(:quit)
        invoke_command(cli, 'xit')
      end
    end

    describe 'log command' do
      it 'delegates to LogCommand with no arguments' do
        mock_log_command = instance_double(WifiWand::LogCommand)
        expect(cli).to receive(:resolve_command).with('log').and_return(mock_log_command)
        expect(mock_log_command).to receive(:call)
        invoke_command(cli, 'log')
      end

      it 'delegates to LogCommand with arguments' do
        mock_log_command = instance_double(WifiWand::LogCommand)
        expect(cli).to receive(:resolve_command).with('log').and_return(mock_log_command)
        expect(mock_log_command).to receive(:call).with('--interval', '2', '--file')
        invoke_command(cli, 'log', '--interval', '2', '--file')
      end

      it 'respects verbose flag from initialization' do
        verbose_opts = create_cli_options(verbose: true)
        verbose_cli = described_class.new(verbose_opts)
        mock_log_command = instance_double(WifiWand::LogCommand)
        expect(verbose_cli).to receive(:resolve_command).with('log').and_return(mock_log_command)
        expect(mock_log_command).to receive(:call)
        invoke_command(verbose_cli, 'log')
      end

      it 'prints log command help without starting the logger' do
        mock_log_command = instance_double(WifiWand::LogCommand)
        expect(cli).to receive(:resolve_command).with('log').and_return(mock_log_command)
        expect(mock_log_command).to receive(:call).with('--help')
        invoke_command(cli, 'log', '--help')
      end

      it 'passes output stream to LogCommand (file-only logic handled in execute)' do
        mock_log_command = instance_double(WifiWand::LogCommand)
        expect(cli).to receive(:resolve_command).with('log').and_return(mock_log_command)
        expect(mock_log_command).to receive(:call).with('--file')
        invoke_command(cli, 'log', '--file')
      end
    end
  end
end
