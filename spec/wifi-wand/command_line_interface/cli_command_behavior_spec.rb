# frozen_string_literal: true

require 'json'
require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface do
  include_context 'for command line interface tests'

  describe 'connect command with saved passwords' do
    before do
      allow(mock_model).to receive(:connect).and_return(nil)
    end

    it 'shows message when saved password is used in non-interactive mode' do
      network_name = 'SavedNetwork'
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(true)

      expect { invoke_command(cli, 'connect', network_name) }
        .to output(/Using saved password for 'SavedNetwork'/).to_stdout
    end

    it 'does not show message when saved password is not used' do
      network_name = 'TestNetwork'
      password = 'explicit_password'
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(false)

      expect { invoke_command(cli, 'connect', network_name, password) }
        .not_to output(/Using saved password/).to_stdout
    end

    it 'does not show message in interactive mode even when saved password is used' do
      network_name = 'SavedNetwork'

      allow(interactive_cli.model).to receive(:connect).with(network_name, nil)
      allow(interactive_cli.model).to receive(:last_connection_used_saved_password?).and_return(true)

      expect { invoke_command(interactive_cli, 'connect', network_name) }
        .not_to output(/Using saved password/).to_stdout
    end
  end

  describe 'resource management commands' do
    let(:mock_resource_manager) { double('resource_manager') }

    before do
      allow(WifiWand::Helpers::ResourceManager).to receive(:new).and_return(mock_resource_manager)
    end

    describe 'ropen command' do
      it 'displays help when no resource codes provided' do
        allow(mock_resource_manager).to receive(:available_resources_help)
          .and_return('Available resources help text')

        expect { invoke_command(cli, 'ropen') }.to output("Available resources help text\n").to_stdout
      end

      it 'returns help text directly in interactive mode with no arguments' do
        help_text = 'Available resources help text'
        allow(mock_resource_manager).to receive(:available_resources_help).and_return(help_text)

        result = invoke_command(interactive_cli, 'ropen')
        expect(result).to eq(help_text)
      end

      it 'opens valid resources and reports success' do
        opened_resources = [
          double('resource', code: 'ipw', description: 'What is My IP'),
          double('resource', code: 'spe', description: 'Speed Test'),
        ]

        allow(mock_resource_manager).to receive(:open_resources_by_codes)
          .with(mock_model, 'ipw', 'spe')
          .and_return({ opened_resources: opened_resources, invalid_codes: [] })

        expect { invoke_command(cli, 'ropen', 'ipw', 'spe') }.not_to output.to_stdout
      end

      it 'displays error message for invalid resource codes' do
        allow(mock_resource_manager).to receive(:open_resources_by_codes)
          .with(mock_model, 'invalid1', 'invalid2')
          .and_return({ opened_resources: [], invalid_codes: %w[invalid1 invalid2] })

        allow(mock_resource_manager).to receive(:invalid_codes_error)
          .with(%w[invalid1 invalid2])
          .and_return("Invalid resource codes: 'invalid1', 'invalid2'")

        expect do
          invoke_command(cli, 'ropen', 'invalid1', 'invalid2')
        end.to output("Invalid resource codes: 'invalid1', 'invalid2'\n").to_stderr
      end

      it 'handles mixed valid and invalid codes' do
        opened_resources = [double('resource', code: 'ipw', description: 'What is My IP')]

        allow(mock_resource_manager).to receive(:open_resources_by_codes)
          .with(mock_model, 'ipw', 'invalid')
          .and_return({ opened_resources: opened_resources, invalid_codes: ['invalid'] })

        allow(mock_resource_manager).to receive(:invalid_codes_error)
          .with(['invalid'])
          .and_return("Invalid resource code: 'invalid'")

        expect { invoke_command(cli, 'ropen', 'ipw', 'invalid') }
          .to output("Invalid resource code: 'invalid'\n").to_stderr
      end
    end
  end

  describe 'QR code generation edge cases' do
    describe 'qr command' do
      context 'with symbol argument for ANSI output' do
        it 'returns ANSI string in interactive mode and does not print' do
          ansi_content = "[QR-ANSI]\nLINE2\n"
          allow(interactive_cli.model).to receive(:generate_qr_code)
            .with('-', hash_including(delivery_mode: :return, password: nil)).and_return(ansi_content)

          result = nil
          expect { result = invoke_command(interactive_cli, 'qr', :-) }.not_to output.to_stdout
          expect(result).to eq(ansi_content)
        end
      end

      context 'when in non-interactive stdout mode' do
        it 'prints ANSI via model and returns nil' do
          allow(mock_model).to receive(:generate_qr_code)
            .with('-', hash_including(delivery_mode: :print, password: nil)) do
            $stdout.print("[QR-ANSI]\n")
            '-'
          end

          result = nil
          captured = silence_output do |stdout, _stderr|
            result = invoke_command(cli, 'qr', '-')
            stdout.string
          end

          expect(result).to be_nil
          expect(captured).to eq("[QR-ANSI]\n")
        end
      end

      context 'when handling file overwrite scenarios' do
        let(:filename) { 'test.png' }
        let(:file_exists_error) { WifiWand::Error.new("File #{filename} already exists") }

        before do
          allow(mock_model).to receive(:generate_qr_code).with(filename,
            hash_including(password: nil)).and_raise(file_exists_error)
          allow($stdin).to receive(:tty?).and_return(true)
        end

        shared_examples 'user confirms overwrite' do |user_input|
          it "proceeds with overwrite when user enters '#{user_input.strip}'" do
            allow(mock_model).to receive(:generate_qr_code).with(filename,
              hash_including(overwrite: true, password: nil)).and_return(filename)
            allow($stdin).to receive(:gets).and_return(user_input)

            captured = silence_output do |stdout, _stderr|
              invoke_command(cli, 'qr', filename)
              stdout.string
            end
            expect(captured).to match(/QR code generated: #{filename}/)
          end
        end

        shared_examples 'user declines overwrite' do |user_input|
          it "returns nil when user enters '#{user_input.strip}'" do
            allow($stdin).to receive(:gets).and_return(user_input)

            result = silence_output { invoke_command(cli, 'qr', filename) }
            expect(result).to be_nil
          end
        end

        it 'prompts for overwrite confirmation when file exists' do
          allow(mock_model).to receive(:generate_qr_code).with(filename,
            hash_including(overwrite: true, password: nil)).and_return(filename)
          allow($stdin).to receive(:gets).and_return("y\n")

          captured = silence_output do |stdout, _stderr|
            invoke_command(cli, 'qr', filename)
            stdout.string
          end
          expect(captured).to match(/Output file exists. Overwrite\? \[y\/N\]: /)
        end

        it_behaves_like 'user confirms overwrite', "y\n"
        it_behaves_like 'user confirms overwrite', "yes\n"
        it_behaves_like 'user declines overwrite', "n\n"
        it_behaves_like 'user declines overwrite', "\n"

        it 're-raises non-overwrite errors' do
          allow(mock_model).to receive(:generate_qr_code).with('other.png',
            hash_including(password: nil)).and_raise(
            WifiWand::Error.new('Network connection failed')
          )

          expect { invoke_command(cli, 'qr', 'other.png') }
            .to raise_error(WifiWand::Error, 'Network connection failed')
        end
      end
    end
  end

  describe 'status command interactive mode' do
    context 'when in interactive mode' do
      it 'outputs status line to out_stream and returns nil' do
        status_data = { wifi_on: true, network_name: 'TestNet' }
        out_stream = StringIO.new
        interactive_opts = interactive_options.dup
        interactive_opts.out_stream = out_stream
        cli = described_class.new(interactive_opts)

        allow(cli.model).to receive(:status_line_data).and_return(status_data)
        allow(cli.output_support).to receive(:status_line).with(status_data)
          .and_return('WiFi: ON | Network: "TestNet"')

        result = invoke_command(cli, 'status')
        expect(result).to be_nil
        expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
      end
    end
  end

  describe 'command delegation' do
    command_test_cases = [
      { command_name: 'wifi_on', model_method: :wifi_on?, return_value: true,
        non_interactive_output: "Wifi on: true\n" },
      { command_name: 'on', model_method: :wifi_on },
      { command_name: 'off', model_method: :wifi_off },
      { command_name: 'disconnect', model_method: :disconnect },
      { command_name: 'cycle', model_method: :cycle_network },
      { command_name: 'avail_nets', model_method: :available_network_names, skip_non_interactive: true },
      { command_name: 'info', model_method: :wifi_info, return_value: { 'status' => 'connected' },
        non_interactive_output: /status.*connected/m },
      { command_name: 'ci', model_method: :internet_connectivity_state, return_value: :reachable,
        non_interactive_output: "Internet connectivity: reachable\n" },
      { command_name: 'qr', model_method: :generate_qr_code, return_value: 'TestNetwork-qr-code.png',
        non_interactive_output: "QR code generated: TestNetwork-qr-code.png\n" },
    ].freeze

    command_test_cases.each do |tc|
      describe "#{tc[:command_name]} command" do
        if tc[:non_interactive_output]
          it_behaves_like 'interactive vs non-interactive command', tc[:command_name], tc[:model_method],
            {
              return_value:          tc[:return_value],
              non_interactive_tests: {
                'outputs formatted message' => {
                  model_return:    tc[:return_value],
                  expected_output: tc[:non_interactive_output],
                },
              },
            }
        elsif !tc[:skip_non_interactive]
          it_behaves_like 'simple command delegation', tc[:command_name], tc[:model_method]
        end
      end
    end

    describe 'avail_nets command' do
      context 'when wifi is on' do
        before { allow(mock_model).to receive(:wifi_on?).and_return(true) }

        it_behaves_like 'interactive vs non-interactive command', 'avail_nets', :available_network_names, {
          return_value:          %w[TestNet1 TestNet2],
          non_interactive_tests: {
            'outputs formatted available networks message' => {
              model_return:    %w[TestNet1 TestNet2],
              expected_output: /Available networks.*descending signal strength.*OS scan.*TestNet1.*TestNet2/m,
            },
          },
        }

        it 'outputs a clear empty-scan message when no networks are returned' do
          allow(mock_model).to receive(:available_network_names).and_return([])
          allow(mock_model).to receive(:is_a?).with(WifiWand::MacOsModel).and_return(true)

          expect do
            invoke_command(cli, 'avail_nets')
          end.to output(/No visible networks were found.*Location Services authorization/im).to_stdout
        end
      end

      context 'when wifi is off' do
        before do
          allow(mock_model).to receive(:wifi_on?).and_return(false)
          allow(mock_model).to receive(:available_network_names)
            .and_raise(WifiWand::Error.new('WiFi is off, cannot scan for available networks.'))
        end

        it 'outputs wifi off message' do
          expect { invoke_command(cli, 'avail_nets') }
            .to output("WiFi is off, cannot scan for available networks.\n").to_stdout
        end
      end
    end

    describe 'ci command' do
      it_behaves_like 'interactive vs non-interactive command', 'ci', :internet_connectivity_state, {
        return_value:          :indeterminate,
        non_interactive_tests: {
          'renders an indeterminate connectivity result explicitly' => {
            model_return:    :indeterminate,
            expected_output: "Internet connectivity: indeterminate\n",
          },
        },
      }
    end

    describe 'network_name command' do
      context 'when connected to a network' do
        it 'outputs current network name' do
          allow(mock_model).to receive(:connected_network_name).and_return('MyNetwork')
          expect { invoke_command(cli, 'network_name') }
            .to output(/Network.*SSID.*name.*MyNetwork/).to_stdout
        end
      end

      context 'when not connected to any network' do
        it 'outputs none message' do
          allow(mock_model).to receive(:connected_network_name).and_return(nil)
          expect { invoke_command(cli, 'network_name') }.to output(/Network.*SSID.*name.*none/).to_stdout
        end
      end
    end
  end

  describe 'nameserver commands' do
    describe 'nameservers command' do
      context 'when getting nameservers (no args or get)' do
        it 'outputs current nameservers' do
          nameservers = ['8.8.8.8', '1.1.1.1']
          allow(mock_model).to receive(:nameservers).and_return(nameservers)

          expect { invoke_command(cli, 'nameservers') }
            .to output("Nameservers: 8.8.8.8, 1.1.1.1\n").to_stdout
        end

        it 'outputs none message when no nameservers' do
          allow(mock_model).to receive(:nameservers).and_return([])

          expect { invoke_command(cli, 'nameservers') }.to output("Nameservers: [None]\n").to_stdout
        end

        it 'handles explicit get command' do
          nameservers = ['8.8.8.8']
          allow(mock_model).to receive(:nameservers).and_return(nameservers)

          expect { invoke_command(cli, 'nameservers', 'get') }
            .to output("Nameservers: 8.8.8.8\n").to_stdout
        end
      end

      context 'when clearing nameservers' do
        it 'calls set_nameservers with clear' do
          expect(mock_model).to receive(:set_nameservers).with(:clear)
          invoke_command(cli, 'nameservers', 'clear')
        end
      end

      context 'when setting nameservers' do
        it 'calls set_nameservers with provided addresses' do
          new_servers = ['9.9.9.9', '8.8.4.4']
          expect(mock_model).to receive(:set_nameservers).with(new_servers)
          invoke_command(cli, 'nameservers', *new_servers)
        end
      end
    end
  end

  describe 'preferred networks commands' do
    describe 'pref_nets command' do
      it 'outputs formatted preferred networks list' do
        networks = %w[Network1 Network2]
        allow(mock_model).to receive(:preferred_networks).and_return(networks)

        expect { invoke_command(cli, 'pref_nets') }.to output(/Network1.*Network2/m).to_stdout
      end
    end

    describe 'password command' do
      it 'outputs password when network has stored password' do
        network = 'TestNetwork'
        password = 'secret123'
        allow(mock_model).to receive(:preferred_network_password).with(network).and_return(password)

        expect do
          invoke_command(cli, 'password', network)
        end.to output(/Preferred network.*TestNetwork.*stored password.*secret123/m).to_stdout
      end

      it 'outputs no password message when network has no stored password' do
        network = 'TestNetwork'
        allow(mock_model).to receive(:preferred_network_password).with(network).and_return(nil)

        expect do
          invoke_command(cli, 'password', network)
        end.to output(/Preferred network.*TestNetwork.*no stored password/m).to_stdout
      end
    end

    describe 'forget command' do
      it 'removes specified networks and outputs result' do
        networks_to_remove = %w[Network1 Network2]
        removed_networks = ['Network1', 'Network1 1']

        expect(mock_model).to receive(:remove_preferred_networks).with(*networks_to_remove)
          .and_return(removed_networks)
        expect { invoke_command(cli, 'forget', *networks_to_remove) }
          .to output(/Removed networks.*Network1/m).to_stdout
      end
    end
  end

  describe 'timing command' do
    describe 'till command' do
      it 'calls model till method with target status' do
        expect(mock_model).to receive(:till).with(
          :wifi_on,
          timeout_in_secs:                         nil,
          wait_interval_in_secs:                   nil,
          stringify_permitted_values_in_error_msg: true
        )
        invoke_command(cli, 'till', 'wifi_on')
      end

      it 'calls model till method with target status and wait interval' do
        expect(mock_model).to receive(:till).with(
          :internet_on,
          timeout_in_secs:                         2.5,
          wait_interval_in_secs:                   nil,
          stringify_permitted_values_in_error_msg: true
        )
        invoke_command(cli, 'till', 'internet_on', '2.5')
      end

      context 'when validating arguments' do
        it 'raises ConfigurationError when no arguments provided' do
          expect { invoke_command(cli, 'till') }.to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Missing target status argument')
            expect(error.message).to include(
              'States: wifi_on, wifi_off, associated, disassociated, internet_on, internet_off'
            )
            expect(error.message).to include('Use')
            expect(error.message).to include('help')
          end
        end

        it 'raises ConfigurationError when first argument is nil' do
          expect { invoke_command(cli, 'till', nil) }
            .to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Missing target status argument')
          end
        end

        it 'raises ConfigurationError when timeout is not numeric' do
          expect { invoke_command(cli, 'till', 'wifi_on', 'invalid') }
            .to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid timeout value')
            expect(error.message).to include('invalid')
            expect(error.message).to include('must be a number')
          end
        end

        it 'raises ConfigurationError when interval is not numeric' do
          expect { invoke_command(cli, 'till', 'wifi_on', '10', 'bad_value') }
            .to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid interval value')
            expect(error.message).to include('bad_value')
            expect(error.message).to include('must be a number')
          end
        end

        it 'raises ConfigurationError when timeout is negative' do
          expect { invoke_command(cli, 'till', 'wifi_on', '-1') }
            .to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid timeout value')
            expect(error.message).to include('-1')
            expect(error.message).to include('must be non-negative')
          end
        end

        it 'raises ConfigurationError when interval is negative' do
          expect { invoke_command(cli, 'till', 'wifi_on', '10', '-0.1') }
            .to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid interval value')
            expect(error.message).to include('-0.1')
            expect(error.message).to include('must be non-negative')
          end
        end

        it 'accepts valid numeric timeout as string' do
          expect(mock_model).to receive(:till).with(
            :wifi_on,
            timeout_in_secs:                         30.0,
            wait_interval_in_secs:                   nil,
            stringify_permitted_values_in_error_msg: true
          )
          expect { invoke_command(cli, 'till', 'wifi_on', '30') }.not_to raise_error
        end

        it 'accepts valid numeric timeout and interval as strings' do
          expect(mock_model).to receive(:till).with(
            :wifi_off,
            timeout_in_secs:                         20.0,
            wait_interval_in_secs:                   0.5,
            stringify_permitted_values_in_error_msg: true
          )
          expect { invoke_command(cli, 'till', 'wifi_off', '20', '0.5') }.not_to raise_error
        end
      end
    end
  end
end
