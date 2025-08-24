require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/command_registry'

describe WifiWand::CommandLineInterface::CommandRegistry do

  let(:expected_commands) do [
    ['a', 'avail_nets'],
    ['ci', 'ci'],
    ['co', 'connect'],
    ['cy', 'cycle'],
    ['d', 'disconnect'],
    ['f', 'forget'],
    ['h', 'help'],
    ['i', 'info'],
    ['l', 'ls_avail_nets'],
    ['na', 'nameservers'],
    ['ne', 'network_name'],
    ['of', 'off'],
    ['on', 'on'],
    ['ro', 'ropen'],
    ['pa', 'password'],
    ['pr', 'pref_nets'],
    ['q', 'quit'],
    ['s', 'status'],
    ['t', 'till'],
    ['u', 'url'],
    ['w', 'wifi_on'],
    ['x', 'xit']
  ] end

  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::CommandRegistry
      
      # Mock the PROJECT_URL constant
      const_set(:PROJECT_URL, 'https://github.com/test/test') unless defined?(PROJECT_URL)
      
      # Mock command methods for testing
      attr_reader :called_commands
      
      def initialize
        @called_commands = []
      end
      
      # Mock all the cmd_* methods
      %w[a ci co cy d f h i l na ne of on ro pa pr q t u w x].each do |cmd|
        define_method("cmd_#{cmd}") do |*args|
          @called_commands << { command: cmd, args: args }
          "#{cmd}_result"
        end
      end
    end
  end

  subject { test_class.new }

  describe 'Command structure and #commands' do
    it 'defines Command struct correctly' do
      command = WifiWand::CommandLineInterface::CommandRegistry::Command.new('a', 'avail', -> { 'test' })
      
      expect(command.min_string).to eq('a')
      expect(command.max_string).to eq('avail')
      expect(command.action).to be_a(Proc)
      expect(command.action.call).to eq('test')
    end

    it 'returns an array of Command objects' do
      commands = subject.commands
      expect(commands).to be_an(Array)
      expect(commands).to all(be_a(WifiWand::CommandLineInterface::CommandRegistry::Command))
    end

    it 'includes all expected commands' do
      command_map = subject.commands.map { |cmd| [cmd.min_string, cmd.max_string] }
      missing_commands = expected_commands - command_map
      expect(missing_commands).to be_empty, "Missing commands: #{missing_commands.inspect}"
    end

    it 'does not include any unexpected commands' do
      command_map = subject.commands.map { |cmd| [cmd.min_string, cmd.max_string] }
      unexpected_commands = command_map - expected_commands
      expect(unexpected_commands).to be_empty, "Unexpected commands: #{unexpected_commands.inspect}"
    end
  end

  describe '#find_command_action' do
    it 'finds commands by various match types' do
      # Exact min_string match
      action = subject.find_command_action('a')
      expect(action).to be_a(Proc)
      expect(action.call).to eq('a_result')
      
      # Exact max_string match  
      action = subject.find_command_action('avail_nets')
      expect(action).to be_a(Proc)
      expect(action.call).to eq('a_result')
      
      # Partial max_string match
      %w[avail conn disconne].each do |partial|
        expect(subject.find_command_action(partial)).to be_a(Proc)
      end
    end

    it 'handles edge cases for command matching' do
      # Minimum string length requirements
      expect(subject.find_command_action('c')).to be_nil  # 'co' is minimum for connect
      expect(subject.find_command_action('co')).not_to be_nil
      
      # Non-matching strings
      ['', 'nonexistent', 'xyz'].each do |bad_input|
        expect(subject.find_command_action(bad_input)).to be_nil
      end
      
      # Case sensitivity
      expect(subject.find_command_action('INFO')).to be_nil
      expect(subject.find_command_action('Info')).to be_nil
      
      # Progressive matching
      %w[i in inf info].each do |partial|
        expect(subject.find_command_action(partial)).not_to be_nil, "Expected '#{partial}' to match info command"
      end
      
      # Ambiguous matches (first match wins)
      action = subject.find_command_action('qui')  # Should match 'quit'
      expect(action).not_to be_nil
      expect(action.call).to eq('q_result')
    end
  end

  describe '#attempt_command_action' do
    let(:error_handler_called) { [] }
    let(:error_handler) { -> { error_handler_called << true } }

    it 'calls error handler for unknown commands' do
      result = subject.attempt_command_action('unknown_command', &error_handler)
      expect(result).to be_nil
      expect(error_handler_called).to eq([true])
    end

    it 'does not call error handler for valid commands' do
      result = subject.attempt_command_action('info', &error_handler)
      expect(result).to eq('i_result')
      expect(error_handler_called).to be_empty
    end

    it 'raises error when no action found and no error handler provided' do
      expect { subject.attempt_command_action('unknown_command') }.to raise_error(NoMethodError)
    end

    it 'works with partial command matches' do
      result = subject.attempt_command_action('conn', 'MyNetwork')
      expect(result).to eq('co_result')
      expect(subject.called_commands.last).to eq({
        command: 'co',
        args: ['MyNetwork']
      })
    end
  end
end