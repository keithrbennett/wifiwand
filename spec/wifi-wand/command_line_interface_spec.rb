require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface do

  # Mock the model to avoid real OS interactions during CLI tests
  let(:mock_model) { 
    double('model', 
      verbose_mode: false,
      wifi_on?: true,
      available_network_names: ['TestNet1', 'TestNet2'],
      wifi_info: {'status' => 'connected'},
      connected_to_internet?: true
    ) 
  }
  let(:mock_os) { double('os', create_model: mock_model) }
  let(:options) { OpenStruct.new(verbose: false, wifi_interface: nil, interactive_mode: false) }

  before(:each) do
    # Mock OS detection to avoid real system calls
    allow_any_instance_of(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
    # Prevent interactive shell from starting
    allow_any_instance_of(WifiWand::CommandLineInterface).to receive(:run_shell)
  end

  subject { described_class.new(options) }

  describe 'initialization' do
    it 'raises NoSupportedOSError when no OS is detected' do
      allow_any_instance_of(WifiWand::OperatingSystems).to receive(:current_os).and_return(nil)
      
      expect { described_class.new(options) }.to raise_error(WifiWand::NoSupportedOSError)
    end


    it 'sets interactive mode correctly' do
      options.interactive_mode = true
      cli = described_class.new(options)
      expect(cli.interactive_mode).to be(true)
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
        expect(subject).to receive(:exit).with(-1)
        expect { subject.validate_command_line }.to output(/Syntax is:/).to_stdout
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
        actions = %w[conn connec connect].map { |s| subject.find_command_action(s) }

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
        expect(subject.find_command_action('c')).to be_nil  # Too short
        expect(subject.find_command_action('co')).not_to be_nil  # Minimum length
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
        
        expect { subject.process_command_line }.to raise_error(WifiWand::CommandLineInterface::BadCommandError) do |error|
          expect(error.message).to include('Unrecognized command')
          expect(error.message).to include('invalid_command')
          expect(error.message).to include('arg1')
          expect(error.message).to include('arg2')
        end
      end

      it 'passes command arguments correctly' do
        stub_const('ARGV', ['connect', 'TestNetwork', 'password123'])
        allow(subject).to receive(:cmd_co).with('TestNetwork', 'password123').and_return('connected')
        
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

end