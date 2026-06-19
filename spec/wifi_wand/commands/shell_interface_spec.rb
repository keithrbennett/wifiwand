# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/shell_interface'
require_relative '../../../lib/wifi_wand/repl_context'
require 'stringio'

describe WifiWand::Commands::ShellInterface do
  subject { test_class.new }

  let(:test_class) do
    Class.new do
      include WifiWand::Commands::ShellInterface

      attr_accessor :interactive_mode

      def out_stream = @out_stream ||= StringIO.new

      def resolve_command(_name) = nil

      def initialize
        @interactive_mode = true
        @err_stream = StringIO.new
      end
    end
  end

  def mock_pry_session
    pry_config = double('pry_config')
    allow(pry_config).to receive(:command_prefix=)
    allow(pry_config).to receive(:print=)
    allow(pry_config).to receive(:exception_handler=)
    stub_const('Pry', double('Pry', config: pry_config))

    mock_context = double('repl_context')
    allow(WifiWand::ReplContext).to receive(:new).with(subject).and_return(mock_context)
    allow(mock_context).to receive(:pry)
    mock_context
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
    it 'outputs interactive shell guidance before starting pry session' do
      allow(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')
      mock_pry_session

      subject.run_shell
      expect(subject.out_stream.string).to eq(
        "#{WifiWand::Commands::ShellInterface::STARTUP_MESSAGE}\n\n"
      )
    end

    it 'requires pry gem' do
      expect(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')
      mock_pry_session

      subject.run_shell
    end

    it 'requires amazing_print gem' do
      allow(subject).to receive(:require).with('pry')
      expect(subject).to receive(:require).with('amazing_print')
      mock_pry_session

      subject.run_shell
    end

    it 'creates a ReplContext with itself and opens a pry session on it' do
      allow(subject).to receive(:require)
      mock_context = mock_pry_session
      expect(WifiWand::ReplContext).to receive(:new).with(subject).and_return(mock_context)
      expect(mock_context).to receive(:pry)

      subject.run_shell
    end

    it 'configures an exception handler that prints the exception message' do
      captured_handler = nil
      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=)
      allow(pry_config).to receive(:exception_handler=) { |proc| captured_handler = proc }
      stub_const('Pry', double('Pry', config: pry_config))

      mock_context = double('repl_context')
      allow(WifiWand::ReplContext).to receive(:new).and_return(mock_context)
      allow(mock_context).to receive(:pry)

      allow(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')

      subject.run_shell

      io = StringIO.new
      ex = RuntimeError.new('boom')
      captured_handler.call(io, ex, nil)
      expect(io.string).to include('boom')
    end

    it 'suppresses explicit silent command results in pry output' do
      captured_print = nil
      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=) { |printer| captured_print = printer }
      allow(pry_config).to receive(:exception_handler=)
      stub_const('Pry', double('Pry', config: pry_config))

      mock_context = double('repl_context')
      allow(WifiWand::ReplContext).to receive(:new).and_return(mock_context)
      allow(mock_context).to receive(:pry)

      allow(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')

      subject.run_shell

      io = StringIO.new
      captured_print.call(io, WifiWand::Commands::SILENT_RESULT, nil)
      expect(io.string).to be_empty
    end

    it 'returns 0 when pry finishes normally' do
      allow(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')
      mock_pry_session

      expect(subject.run_shell).to eq(0)
    end

    it 'returns 0 when the shell exit signal is thrown during the pry session' do
      allow(subject).to receive(:require).with('pry')
      allow(subject).to receive(:require).with('amazing_print')

      pry_config = double('pry_config')
      allow(pry_config).to receive(:command_prefix=)
      allow(pry_config).to receive(:print=)
      allow(pry_config).to receive(:exception_handler=)
      stub_const('Pry', double('Pry', config: pry_config))

      mock_context = double('repl_context')
      allow(WifiWand::ReplContext).to receive(:new).and_return(mock_context)
      allow(mock_context).to receive(:pry) { throw(:wifiwand_shell_exit, 0) }

      expect(subject.run_shell).to eq(0)
    end
  end
end
