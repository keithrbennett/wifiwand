# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/shell_interface'
require 'stringio'

describe WifiWand::CommandLineInterface::ShellInterface do
  # Create a test class that includes the module
  subject { test_class.new }

  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::ShellInterface

      # Mock required methods from CommandLineInterface
      def attempt_command_action(command, *_args, &block)
        case command
        when 'info'
          'mock info result'
        when 'quit', 'q'
          quit
        else
          block&.call if block
          nil
        end
      end

      def print_help = puts 'Mock help text'

      # Mock interactive_mode for testing
      attr_accessor :interactive_mode

      def out_stream = @out_stream ||= StringIO.new

      def initialize
        @interactive_mode = true
        @err_stream = StringIO.new
      end
    end
  end


  describe '#method_missing' do
    it 'attempts to execute commands via attempt_command_action' do
      # Mock the command execution
      expect(subject).to receive(:attempt_command_action).with('invalid_command', 'arg1', 'arg2') do |&block|
        block.call if block  # Call the error handler
        nil
      end

      # Should raise NoMethodError
      expect { subject.invalid_command('arg1', 'arg2') }
        .to raise_error(NoMethodError, /is not a valid command or option/)
    end

    it 'does not interfere with known commands' do
      # Should not call the original method_missing for successful commands
      expect(subject).to receive(:attempt_command_action).with('info').and_return('info result')

      result = subject.info
      expect(result).to eq('info result')
    end

    it 'prints error for unknown commands' do
      expect { subject.unknown_command }.to raise_error(NoMethodError, /is not a valid command or option/)
    end

    it 'suggests string literal usage for unknown commands' do
      # The suggestion is part of the error message in the current implementation
      expect { subject.unknown_command }.to raise_error(NoMethodError,
        /If you intended it as an argument to a command, it may be invalid or need quotes./)
    end
  end

  describe '#quit' do
    it 'throws a shell exit signal with code 0 when in interactive mode' do
      subject.interactive_mode = true
      expect { subject.quit }.to throw_symbol(:wifiwand_shell_exit, 0)
    end

    it 'prints error message and returns 1 when not in interactive mode' do
      subject.interactive_mode = false
      result = subject.quit
      expect(result).to eq(1)
      expect(subject.instance_variable_get(:@err_stream).string)
        .to include('This command can only be run in shell mode.')
    end
  end

  describe '#run_shell' do
    # NOTE: run_shell uses pry binding which is difficult to test comprehensively
    # These tests focus on the basic setup and requirements

    def mock_pry_session
      # Mock pry completely
      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=)
      allow(pry_config).to receive(:exception_handler=)
      pry_class = double('Pry', config: pry_config)
      stub_const('Pry', pry_class)

      mock_binding = double('binding')
      allow(subject).to receive(:binding).and_return(mock_binding)
      allow(mock_binding).to receive(:pry)
    end

    it 'outputs a 1-line help message before starting pry session' do
      allow(subject).to receive(:require).with('pry')
      mock_pry_session

      subject.run_shell
      expect(subject.out_stream.string).to eq("For help, type 'h[Enter]' or 'help[Enter]'.\n")
    end

    it 'requires pry gem' do
      expect(subject).to receive(:require).with('pry')
      mock_pry_session

      subject.run_shell
    end

    it 'configures an exception handler that prints the exception message' do
      # Capture handler proc assigned by run_shell
      captured_handler = nil

      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=)
      allow(pry_config).to receive(:exception_handler=) { |proc| captured_handler = proc }
      pry_class = double('Pry', config: pry_config)
      stub_const('Pry', pry_class)

      allow(subject).to receive(:require).with('pry')
      mock_binding = double('binding', pry: nil)
      allow(subject).to receive(:binding).and_return(mock_binding)

      subject.run_shell

      # Call the captured handler and assert it prints exception message
      io = StringIO.new
      ex = RuntimeError.new('boom')
      captured_handler.call(io, ex, nil)
      expect(io.string).to include('boom')
    end

    it 'returns 0 when pry finishes normally' do
      allow(subject).to receive(:require).with('pry')
      mock_pry_session

      expect(subject.run_shell).to eq(0)
    end

    it 'returns 0 when quit throws the shell exit signal' do
      allow(subject).to receive(:require).with('pry')

      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=)
      allow(pry_config).to receive(:exception_handler=)
      pry_class = double('Pry', config: pry_config)
      stub_const('Pry', pry_class)

      mock_binding = double('binding')
      allow(subject).to receive(:binding).and_return(mock_binding)
      allow(mock_binding).to receive(:pry) { subject.quit }

      expect(subject.run_shell).to eq(0)
    end
  end
end
