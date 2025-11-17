# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/command_line_interface'
require_relative '../../lib/wifi-wand/commands/log_command'

describe WifiWand::CommandLineInterface do
  include TestHelpers

  # Use factory methods to create standard test fixtures
  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:interactive_options) { create_cli_options(interactive_mode: true) }
  let(:interactive_cli) { described_class.new(interactive_options) }

  # Shared examples for command delegation testing
  shared_examples 'simple command delegation' do |cmd_method, model_method|
    it "calls model #{model_method} method" do
      expect(mock_model).to receive(model_method)
      silence_output { subject.public_send(cmd_method) }
    end
  end

  # Shared examples for interactive vs non-interactive behavior
  shared_examples 'interactive vs non-interactive command' do |cmd_method, model_method, test_cases|
    context 'in interactive mode' do
      it 'returns the result directly' do
        allow(interactive_cli.model).to receive(model_method).and_return(test_cases[:return_value])
        result = interactive_cli.public_send(cmd_method)
        expect(result).to eq(test_cases[:return_value])
      end
    end

    context 'in non-interactive mode' do
      test_cases[:non_interactive_tests].each do |description, test_data|
        it description do
          allow(mock_model).to receive(model_method).and_return(test_data[:model_return])

          # Capture output without displaying it during test runs
          captured_output = silence_output do |stdout, _stderr|
            subject.public_send(cmd_method)
            stdout.string
          end

          # Support both string and regex expectations
          if test_data[:expected_output].is_a?(Regexp)
            expect(captured_output).to match(test_data[:expected_output])
          else
            expect(captured_output).to eq(test_data[:expected_output])
          end
        end
      end
    end
  end

  before(:each) do
    # Mock OS detection to avoid real system calls
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
    # Prevent interactive shell from starting
    allow_any_instance_of(WifiWand::CommandLineInterface).to receive(:run_shell)
  end

  subject { described_class.new(options) }

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

    it 'uses WifiWand.create_model to build the model with derived options' do
      # Ensure create_model is called and returns our mock model
      expect(WifiWand)
        .to receive(:create_model) do |model_options|
          expect(model_options).to be_a(OpenStruct)
          expect(model_options.verbose).to eq(options.verbose)
          expect(model_options.wifi_interface).to eq(options.wifi_interface)
          mock_model
        end

      cli = described_class.new(options)
      expect(cli.model).to eq(mock_model)
    end
  end

  describe 'command validation' do
    before(:each) do
      allow(subject).to receive(:print_help)
      allow(subject).to receive(:exit)
    end

    describe '#validate_command_line' do
      specify 'validation exits with error when no command is provided' do
        stub_const('ARGV', [])
        err_stream = StringIO.new
        opts = options.dup
        opts.err_stream = err_stream
        cli = described_class.new(opts)
        expect(cli).to receive(:exit).with(-1)
        cli.validate_command_line
        expect(err_stream.string).to match(/Syntax is:/)
      end

      specify 'validation does not exit when command is provided' do
        stub_const('ARGV', ['info'])
        expect(subject).not_to receive(:exit)
        expect { subject.validate_command_line }.not_to output.to_stdout
      end
    end
  end

  describe 'command registry and routing' do
    describe 'CommandRegistry module' do
      it 'defines expected commands' do
        commands = subject.commands
        expect(commands).to be_an(Array)

        # Check some key commands exist
        command_strings = commands.map(&:max_string)
        expect(command_strings).to include('info', 'connect', 'disconnect', 'help', 'avail_nets')
      end

      specify 'substrings of commands can be substituted for the full command name' do
        # Partial string matching
        actions = ['conn', 'connec', 'connect'].map { |s| subject.find_command_action(s) }

        all_actions_identical = (actions.uniq.size == 1)
        expect(all_actions_identical).to eq(true)

        # must be callables (Proc, other object with 'call' method)
        expect(all_actions_identical && actions.first.respond_to?(:call)).to eq(true)
      end

      specify 'invalid command strings will return nil' do
        expect(subject.find_command_action('unknown_command')).to be_nil
      end

      specify 'minimum command lengths may be required' do
        # Minimum string length requirements
        expect(subject.find_command_action('c')).to be_nil # Too short
        expect(subject.find_command_action('co')).not_to be_nil # Minimum length
      end
    end

    describe '#attempt_command_action' do
      it 'executes valid commands' do
        allow(subject).to receive(:cmd_i).and_return('info_result')

        result = subject.attempt_command_action('info')
        expect(result).to eq('info_result')
      end

      it 'calls error handler for invalid commands' do
        error_handler_called = false
        error_handler = -> { error_handler_called = true }

        result = subject.attempt_command_action('invalid_command', &error_handler)
        expect(result).to be_nil
        expect(error_handler_called).to be(true)
      end

      it 'passes arguments to command methods' do
        allow(subject).to receive(:cmd_co).with('network', 'password').and_return('connect_result')

        result = subject.attempt_command_action('connect', 'network', 'password')
        expect(result).to eq('connect_result')
      end
    end
  end

  describe 'command line processing' do
    describe '#process_command_line' do
      before(:each) do
        allow(subject).to receive(:print_help)
      end

      it 'processes valid commands' do
        stub_const('ARGV', ['info'])
        allow(subject).to receive(:cmd_i).and_return('info result')

        result = subject.process_command_line
        expect(result).to eq('info result')
      end

      it 'raises BadCommandError for invalid commands' do
        stub_const('ARGV', ['invalid_command', 'arg1', 'arg2'])

        expect { subject.process_command_line }.to raise_error(WifiWand::BadCommandError) do |error|
          expect(error.message).to include('Unrecognized command')
          expect(error.message).to include('invalid_command')
          expect(error.message).to include('arg1')
          expect(error.message).to include('arg2')
        end
      end

      it 'passes command arguments correctly' do
        stub_const('ARGV', ['connect', 'TestNetwork', 'password123'])
        allow(subject).to receive(:cmd_co).with('TestNetwork', 
'password123').and_return('connected')

        result = subject.process_command_line
        expect(result).to eq('connected')
      end

      it 'handles commands with no arguments' do
        stub_const('ARGV', ['info'])
        allow(subject).to receive(:cmd_i).and_return('info_output')

        result = subject.process_command_line
        expect(result).to eq('info_output')
      end
    end
  end

  describe 'connect command with saved passwords' do
    before do
      allow(mock_model).to receive(:connect).and_return(nil)
    end

    it 'shows message when saved password is used in non-interactive mode' do
      network_name = 'SavedNetwork'
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(true)

      # Capture output
      expect {
 subject.cmd_co(network_name) }.to output(/Using saved password for 'SavedNetwork'/).to_stdout
    end

    it 'does not show message when saved password is not used' do
      network_name = 'TestNetwork'
      password = 'explicit_password'
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(false)

      # Should not output message
      expect {
 subject.cmd_co(network_name, password) }.not_to output(/Using saved password/).to_stdout
    end

    it 'does not show message in interactive mode even when saved password is used' do
      network_name = 'SavedNetwork'

      allow(interactive_cli.model).to receive(:connect).with(network_name, nil)
      allow(interactive_cli.model).to receive(:last_connection_used_saved_password?).and_return(true)

      # Should not output message in interactive mode
      expect {
 interactive_cli.cmd_co(network_name) }.not_to output(/Using saved password/).to_stdout
    end
  end

  describe 'resource management commands' do
    let(:mock_resource_manager) { double('resource_manager') }

    before(:each) do
      allow(mock_model).to receive(:resource_manager).and_return(mock_resource_manager)
      allow(mock_model).to receive(:open_resources_by_codes)
      allow(mock_model).to receive(:available_resources_help)
    end

    describe 'cmd_ro (open resources)' do
      it 'displays help when no resource codes provided' do
        allow(mock_model).to receive(:available_resources_help).and_return('Available resources help text')

        expect { subject.cmd_ro }.to output("Available resources help text\n").to_stdout
      end

      it 'returns help text directly in interactive mode with no arguments' do
        help_text = 'Available resources help text'
        allow(interactive_cli.model).to receive(:available_resources_help).and_return(help_text)

        result = interactive_cli.cmd_ro
        expect(result).to eq(help_text)
      end

      it 'opens valid resources and reports success' do
        opened_resources = [
          double('resource', code: 'ipw', description: 'What is My IP'),
          double('resource', code: 'spe', description: 'Speed Test')
        ]

        allow(mock_model).to receive(:open_resources_by_codes)
          .with('ipw', 'spe')
          .and_return({ opened_resources: opened_resources, invalid_codes: [] })

        expect { subject.cmd_ro('ipw', 'spe') }.not_to output.to_stdout
      end

      it 'displays error message for invalid resource codes' do
        allow(mock_model).to receive(:open_resources_by_codes)
          .with('invalid1', 'invalid2')
          .and_return({ opened_resources: [], invalid_codes: ['invalid1', 'invalid2'] })

        allow(mock_resource_manager).to receive(:invalid_codes_error)
          .with(['invalid1', 'invalid2'])
          .and_return("Invalid resource codes: 'invalid1', 'invalid2'")

        expect {
 subject.cmd_ro('invalid1', 
'invalid2') }.to output("Invalid resource codes: 'invalid1', 'invalid2'\n").to_stderr
      end

      it 'handles mixed valid and invalid codes' do
        opened_resources = [double('resource', code: 'ipw', description: 'What is My IP')]

        allow(mock_model).to receive(:open_resources_by_codes)
          .with('ipw', 'invalid')
          .and_return({ opened_resources: opened_resources, invalid_codes: ['invalid'] })

        allow(mock_resource_manager).to receive(:invalid_codes_error)
          .with(['invalid'])
          .and_return("Invalid resource code: 'invalid'")

        expect {
 subject.cmd_ro('ipw', 'invalid') }.to output("Invalid resource code: 'invalid'\n").to_stderr
      end
    end
  end

  describe 'QR code generation edge cases' do
    describe '#cmd_qr' do
      context 'with symbol argument for ANSI output' do
        it 'returns ANSI string in interactive mode and does not print' do
          ansi_content = "[QR-ANSI]\nLINE2\n"
          allow(interactive_cli.model).to receive(:generate_qr_code)
            .with('-', hash_including(delivery_mode: :return, 
password: nil)).and_return(ansi_content)

          expect { @result = interactive_cli.cmd_qr(:'-') }.not_to output.to_stdout
          expect(@result).to eq(ansi_content)
        end
      end

      context 'non-interactive stdout mode' do
        it 'prints ANSI via model and returns nil' do
          # Model handles printing when delivery_mode is :print; CLI should not add extra output
          allow(mock_model).to receive(:generate_qr_code).with('-', 
hash_including(delivery_mode: :print, password: nil)) do
            $stdout.print("[QR-ANSI]\n")
            '-'
          end

          result = nil
          captured = silence_output do |stdout, _stderr|
            result = subject.cmd_qr('-')
            stdout.string
          end

          expect(result).to be_nil
          expect(captured).to eq("[QR-ANSI]\n")
        end
      end

      context 'file overwrite scenarios' do
        let(:filename) { 'test.png' }
        let(:file_exists_error) { WifiWand::Error.new("File #{filename} already exists") }

        before do
          # First call always fails with file exists error
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
              subject.cmd_qr(filename)
              stdout.string
            end
            expect(captured).to match(/QR code generated: #{filename}/)
          end
        end

        shared_examples 'user declines overwrite' do |user_input|
          it "returns nil when user enters '#{user_input.strip}'" do
            allow($stdin).to receive(:gets).and_return(user_input)

            result = silence_output { subject.cmd_qr(filename) }
            expect(result).to be_nil
          end
        end

        it 'prompts for overwrite confirmation when file exists' do
          allow(mock_model).to receive(:generate_qr_code).with(filename, 
hash_including(overwrite: true, password: nil)).and_return(filename)
          allow($stdin).to receive(:gets).and_return("y\n")

          captured = silence_output do |stdout, _stderr|
            subject.cmd_qr(filename)
            stdout.string
          end
          expect(captured).to match(/Output file exists. Overwrite\? \[y\/N\]: /)
        end

        include_examples 'user confirms overwrite', "y\n"
        include_examples 'user confirms overwrite', "yes\n"
        include_examples 'user declines overwrite', "n\n"
        include_examples 'user declines overwrite', "\n"

        it 're-raises non-overwrite errors' do
          # Reset mock for different error
          allow(mock_model).to receive(:generate_qr_code).with('other.png', 
hash_including(password: nil)).and_raise(
            WifiWand::Error.new('Network connection failed')
          )

          expect {
 subject.cmd_qr('other.png') }.to raise_error(WifiWand::Error, 'Network connection failed')
        end
      end
    end
  end

  describe 'status command interactive mode' do
    describe '#cmd_s' do
      context 'in interactive mode' do
        it 'outputs status line to out_stream and returns nil' do
          status_data = { wifi_on: true, network_name: 'TestNet' }
          out_stream = StringIO.new
          interactive_opts = interactive_options.dup
          interactive_opts.out_stream = out_stream
          cli = described_class.new(interactive_opts)

          allow(cli.model).to receive(:status_line_data).and_return(status_data)
          allow(cli).to receive(:status_line).with(status_data).and_return('WiFi: ON | Network: "TestNet"')

          result = cli.cmd_s
          expect(result).to be_nil
          expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
        end
      end
    end
  end

  describe 'command delegation' do
    COMMAND_TEST_CASES = [
      { cmd: :cmd_w,  model_method: :wifi_on?, return_value: true, 
        non_interactive_output: "Wifi on: true\n" },
      { cmd: :cmd_on, model_method: :wifi_on },
      { cmd: :cmd_of, model_method: :wifi_off },
      { cmd: :cmd_d,  model_method: :disconnect },
      { cmd: :cmd_cy, model_method: :cycle_network },
      { cmd: :cmd_a,  model_method: :available_network_names, skip_non_interactive: true },
      { cmd: :cmd_i,  model_method: :wifi_info, return_value: { 'status' => 'connected' }, 
        non_interactive_output: /status.*connected/m },
      { cmd: :cmd_ci, model_method: :connected_to_internet?, return_value: true, 
        non_interactive_output: "Connected to Internet: true\n" },
      { cmd: :cmd_qr, model_method: :generate_qr_code, return_value: 'TestNetwork-qr-code.png', 
        non_interactive_output: "QR code generated: TestNetwork-qr-code.png\n" }
    ]

    COMMAND_TEST_CASES.each do |test_case|
      describe "##{test_case[:cmd]}" do
        if test_case[:non_interactive_output]
          include_examples 'interactive vs non-interactive command', test_case[:cmd], test_case[:model_method], {
            return_value: test_case[:return_value],
            non_interactive_tests: {
              'outputs formatted message' => {
                model_return: test_case[:return_value],
                expected_output: test_case[:non_interactive_output]
              }
            }
          }
        elsif !test_case[:skip_non_interactive]
          include_examples 'simple command delegation', test_case[:cmd], test_case[:model_method]
        end
      end
    end

    describe '#cmd_a (available networks)' do
      context 'when wifi is on' do
        before { allow(mock_model).to receive(:wifi_on?).and_return(true) }

        include_examples 'interactive vs non-interactive command', :cmd_a, :available_network_names, {
          return_value: ['TestNet1', 'TestNet2'],
          non_interactive_tests: {
            'outputs formatted available networks message' => {
              model_return: ['TestNet1', 'TestNet2'],
              expected_output: /Available networks.*descending signal strength.*TestNet1.*TestNet2/m
            }
          }
        }
      end

      context 'when wifi is off' do
        before { allow(mock_model).to receive(:wifi_on?).and_return(false) }

        it 'outputs wifi off message' do
          expect {
 subject.cmd_a }.to output("Wifi is off, cannot see available networks.\n").to_stdout
        end
      end
    end

    describe '#cmd_ne (network name)' do
      context 'when connected to a network' do
        it 'outputs current network name' do
          allow(mock_model).to receive(:connected_network_name).and_return('MyNetwork')
          expect { subject.cmd_ne }.to output(/Network.*SSID.*name.*MyNetwork/).to_stdout
        end
      end

      context 'when not connected to any network' do
        it 'outputs none message' do
          allow(mock_model).to receive(:connected_network_name).and_return(nil)
          expect { subject.cmd_ne }.to output(/Network.*SSID.*name.*none/).to_stdout
        end
      end
    end
  end

  describe 'nameserver commands' do
    describe '#cmd_na (nameserver operations)' do
      context 'when getting nameservers (no args or get)' do
        it 'outputs current nameservers' do
          nameservers = ['8.8.8.8', '1.1.1.1']
          allow(mock_model).to receive(:nameservers).and_return(nameservers)

          expect { subject.cmd_na }.to output("Nameservers: 8.8.8.8, 1.1.1.1\n").to_stdout
        end

        it 'outputs none message when no nameservers' do
          allow(mock_model).to receive(:nameservers).and_return([])

          expect { subject.cmd_na }.to output("Nameservers: [None]\n").to_stdout
        end

        it 'handles explicit get command' do
          nameservers = ['8.8.8.8']
          allow(mock_model).to receive(:nameservers).and_return(nameservers)

          expect { subject.cmd_na('get') }.to output("Nameservers: 8.8.8.8\n").to_stdout
        end
      end

      context 'when clearing nameservers' do
        it 'calls set_nameservers with clear' do
          expect(mock_model).to receive(:set_nameservers).with(:clear)
          subject.cmd_na('clear')
        end
      end

      context 'when setting nameservers' do
        it 'calls set_nameservers with provided addresses' do
          new_servers = ['9.9.9.9', '8.8.4.4']
          expect(mock_model).to receive(:set_nameservers).with(new_servers)
          subject.cmd_na(*new_servers)
        end
      end
    end
  end

  describe 'preferred networks commands' do
    describe '#cmd_pr (preferred networks)' do
      it 'outputs formatted preferred networks list' do
        networks = ['Network1', 'Network2']
        allow(mock_model).to receive(:preferred_networks).and_return(networks)

        expect { subject.cmd_pr }.to output(/Network1.*Network2/m).to_stdout
      end
    end

    describe '#cmd_pa (preferred network password)' do
      it 'outputs password when network has stored password' do
        network = 'TestNetwork'
        password = 'secret123'
        allow(mock_model).to receive(:preferred_network_password).with(network).and_return(password)

        expect {
 subject.cmd_pa(network) }.to output(/Preferred network.*TestNetwork.*stored password.*secret123/m).to_stdout
      end

      it 'outputs no password message when network has no stored password' do
        network = 'TestNetwork'
        allow(mock_model).to receive(:preferred_network_password).with(network).and_return(nil)

        expect {
 subject.cmd_pa(network) }.to output(/Preferred network.*TestNetwork.*no stored password/m).to_stdout
      end
    end

    describe '#cmd_f (forget/remove preferred networks)' do
      it 'removes specified networks and outputs result' do
        networks_to_remove = ['Network1', 'Network2']
        removed_networks = ['Network1']

        expect(mock_model).to receive(:remove_preferred_networks).with(*networks_to_remove).and_return(removed_networks)
        expect {
 subject.cmd_f(*networks_to_remove) }.to output(/Removed networks.*Network1/m).to_stdout
      end
    end
  end

  describe 'timing command' do
    describe '#cmd_t (till)' do
      it 'calls model till method with target status' do
        expect(mock_model).to receive(:till).with(
          :on,
          timeout_in_secs: nil,
          wait_interval_in_secs: nil,
          stringify_permitted_values_in_error_msg: true
        )
        subject.cmd_t('on')
      end

      it 'calls model till method with target status and wait interval' do
        expect(mock_model).to receive(:till).with(
          :connected,
          timeout_in_secs: 2.5,
          wait_interval_in_secs: nil,
          stringify_permitted_values_in_error_msg: true
        )
        subject.cmd_t('connected', '2.5')
      end

      context 'argument validation' do
        it 'raises ConfigurationError when no arguments provided' do
          expect { subject.cmd_t }.to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Missing target status argument')
            expect(error.message).to include('Usage: till conn|disc|on|off')
            expect(error.message).to include('Use')
            expect(error.message).to include('help')
          end
        end

        it 'raises ConfigurationError when first argument is nil' do
          expect { subject.cmd_t(nil) }.to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Missing target status argument')
          end
        end

        it 'raises ConfigurationError when timeout is not numeric' do
          expect {
 subject.cmd_t('on', 'invalid') }.to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid timeout value')
            expect(error.message).to include('invalid')
            expect(error.message).to include('must be a number')
          end
        end

        it 'raises ConfigurationError when interval is not numeric' do
          expect {
 subject.cmd_t('on', '10', 'bad_value') }.to raise_error(WifiWand::ConfigurationError) do |error|
            expect(error.message).to include('Invalid interval value')
            expect(error.message).to include('bad_value')
            expect(error.message).to include('must be a number')
          end
        end

        it 'accepts valid numeric timeout as string' do
          expect(mock_model).to receive(:till).with(
            :on,
            timeout_in_secs: 30.0,
            wait_interval_in_secs: nil,
            stringify_permitted_values_in_error_msg: true
          )
          expect { subject.cmd_t('on', '30') }.not_to raise_error
        end

        it 'accepts valid numeric timeout and interval as strings' do
          expect(mock_model).to receive(:till).with(
            :off,
            timeout_in_secs: 20.0,
            wait_interval_in_secs: 0.5,
            stringify_permitted_values_in_error_msg: true
          )
          expect { subject.cmd_t('off', '20', '0.5') }.not_to raise_error
        end
      end
    end
  end

  describe 'utility commands' do
    describe '#cmd_h (help)' do
      it 'calls print_help method' do
        expect(subject).to receive(:print_help)
        subject.cmd_h
      end
    end

    describe '#cmd_s (status)' do
      let(:status_data) do
        {
          wifi_on: true,
          network_name: 'TestNet',
          tcp_working: true,
          dns_working: true,
          internet_connected: true
        }
      end

      it 'outputs status line when not empty' do
        allow(mock_model).to receive(:status_line_data).and_return(status_data)
        out_stream = StringIO.new
        opts = options.dup
        opts.out_stream = out_stream
        cli = described_class.new(opts)
        allow(cli).to receive(:status_line).with(status_data).and_return('WiFi: ON | Network: "TestNet"')
        cli.cmd_s
        expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
      end

      it 'outputs nothing when status line is empty' do
        allow(mock_model).to receive(:status_line_data).and_return(status_data)
        out_stream = StringIO.new
        opts = options.dup
        opts.out_stream = out_stream
        cli = described_class.new(opts)
        allow(cli).to receive(:status_line).with(status_data).and_return('')
        cli.cmd_s
        expect(out_stream.string).to eq('')
      end
    end

    describe '#cmd_q and #cmd_x (quit/exit)' do
      before { allow(subject).to receive(:quit) }

      it 'cmd_q calls quit method' do
        expect(subject).to receive(:quit)
        subject.cmd_q
      end

      it 'cmd_x calls quit method' do
        expect(subject).to receive(:quit)
        subject.cmd_x
      end
    end

    describe '#cmd_log' do
      it 'delegates to LogCommand with no arguments' do
        mock_log_command = instance_double('WifiWand::LogCommand')
        expect(WifiWand::LogCommand).to receive(:new).with(mock_model, 
output: subject.send(:out_stream), verbose: false).and_return(mock_log_command)
        expect(mock_log_command).to receive(:execute)
        subject.cmd_log
      end

      it 'delegates to LogCommand with arguments' do
        mock_log_command = instance_double('WifiWand::LogCommand')
        expect(WifiWand::LogCommand).to receive(:new).with(mock_model, 
output: subject.send(:out_stream), verbose: false).and_return(mock_log_command)
        expect(mock_log_command).to receive(:execute).with('--interval', '2', '--file')
        subject.cmd_log('--interval', '2', '--file')
      end

      it 'respects verbose flag from initialization' do
        verbose_opts = create_cli_options(verbose: true)
        verbose_cli = described_class.new(verbose_opts)
        mock_log_command = instance_double('WifiWand::LogCommand')
        expect(WifiWand::LogCommand).to receive(:new).with(verbose_cli.model, 
output: verbose_cli.send(:out_stream), verbose: true).and_return(mock_log_command)
        expect(mock_log_command).to receive(:execute)
        verbose_cli.cmd_log
      end

      it 'does not create a log file by default (stdout-only)' do
        # This test ensures that the default behavior only outputs to stdout
        mock_log_command = instance_double('WifiWand::LogCommand')
        expect(WifiWand::LogCommand).to receive(:new) do |model, output:, verbose:|
          expect(output).to eq(subject.send(:out_stream))
          mock_log_command
        end
        expect(mock_log_command).to receive(:execute)
        subject.cmd_log
      end

      it 'passes output stream to LogCommand (file-only logic handled in execute)' do
        # cmd_log always passes the output stream to LogCommand.
        # LogCommand.execute then determines whether to use it based on --file/--stdout options.
        # When --file is used without --stdout, LogCommand.execute passes nil to EventLogger.
        mock_log_command = instance_double('WifiWand::LogCommand')
        expect(WifiWand::LogCommand).to receive(:new).with(mock_model, 
output: subject.send(:out_stream), verbose: false).and_return(mock_log_command)
        expect(mock_log_command).to receive(:execute).with('--file')
        subject.cmd_log('--file')
      end
    end
  end

  describe 'output handling' do
    describe '#handle_output' do
      let(:test_data) { { key: 'value' } }
      let(:human_readable_producer) { -> { 'Human readable output' } }
      let(:processor) { ->(obj) { obj.to_s.upcase } }
      let(:options_with_processor) { create_cli_options(post_processor: processor) }
      let(:cli_with_processor) { described_class.new(options_with_processor) }

      context 'in interactive mode' do
        it 'returns data directly without output' do
          result = interactive_cli.send(:handle_output, test_data, human_readable_producer)
          expect(result).to eq(test_data)
        end
      end

      context 'in non-interactive mode' do
        context 'with post processor' do
          it 'uses post processor and outputs result' do
            # Accept both old Ruby format and new Ruby format
            output = nil
            expect {
              silence_output do |stdout, _stderr|
                cli_with_processor.send(:handle_output, test_data, human_readable_producer)
                output = stdout.string
              end
            }.not_to raise_error
            expect(output).to eq(%Q{{:KEY=>"VALUE"}\n}).or eq(%Q{{KEY: "VALUE"}\n})
          end
        end

        context 'without post processor' do
          it 'uses human readable producer and outputs result' do
            expect {
 subject.send(:handle_output, test_data, 
human_readable_producer) }.to output("Human readable output\n").to_stdout
          end
        end
      end
    end
  end

  describe '#call (main entry point)' do
    before do
      allow(subject).to receive(:validate_command_line)
      allow(subject).to receive(:process_command_line).and_return('command_result')
      allow(subject).to receive(:exit)
      allow(subject).to receive(:help_hint).and_return('Type help for usage')
    end

    it 'validates command line and processes commands successfully' do
      expect(subject).to receive(:validate_command_line)
      expect(subject).to receive(:process_command_line)

      subject.call
    end

    it 'handles BadCommandError with error message and help hint' do
      error = WifiWand::BadCommandError.new('Invalid command')
      # Rebuild CLI with a captured err_stream for this test
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive(:validate_command_line)
      allow(cli).to receive(:help_hint).and_return('Type help for usage')
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli).to receive(:exit).with(-1)
      cli.call
      expect(err_stream.string).to include('Invalid command')
      expect(err_stream.string).to include('Type help for usage')
    end

    it 'handles ConfigurationError with error message' do
      error = WifiWand::ConfigurationError.new('Missing required argument')
      # Rebuild CLI with a captured err_stream for this test
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive(:validate_command_line)
      allow(cli).to receive(:help_hint).and_return('Type help for usage')
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli).to receive(:exit).with(-1)
      cli.call
      expect(err_stream.string).to include('Missing required argument')
      expect(err_stream.string).to include('Type help for usage')
    end

    it 'does not duplicate help hint when error message already contains it' do
      error_msg = 'Missing required argument. Type help for usage'
      error = WifiWand::ConfigurationError.new(error_msg)
      # Rebuild CLI with a captured err_stream for this test
      err_stream = StringIO.new
      opts = options.dup
      opts.err_stream = err_stream
      cli = described_class.new(opts)
      allow(cli).to receive(:validate_command_line)
      allow(cli).to receive(:help_hint).and_return('Type help for usage')
      allow(cli).to receive(:process_command_line).and_raise(error)
      expect(cli).to receive(:exit).with(-1)
      cli.call
      # Count occurrences of the help hint - should only appear once
      hint_count = err_stream.string.scan(/Type help for usage/).length
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
          expect(subject.verbose_mode).to be(false)
        end
      end
    end
  end


end
