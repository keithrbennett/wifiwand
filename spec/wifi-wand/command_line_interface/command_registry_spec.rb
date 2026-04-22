# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/command_registry'

describe WifiWand::CommandMetadata do
  it 'exposes short, long, and alias names' do
    metadata = described_class.new(short_string: 't', long_string: 'test_command')

    expect(metadata.short_string).to eq('t')
    expect(metadata.long_string).to eq('test_command')
    expect(metadata.aliases).to eq(%w[t test_command])
  end
end

describe WifiWand::Command do
  let(:cli) { double('cli') }
  let(:metadata) { WifiWand::CommandMetadata.new(short_string: 't', long_string: 'test_command') }

  it 'returns a fresh command instance when bound' do
    command = described_class.new(metadata: metadata)

    bound_command = command.bind(cli)

    expect(bound_command.metadata).to eq(metadata)
    expect(bound_command).to be_a(described_class)
    expect(bound_command).not_to equal(command)
  end

  it 'binds declared same-name attributes from the cli' do
    command_class = Class.new(described_class) do
      binds :model, :interactive_mode
    end

    model = double('model')
    command_metadata = WifiWand::CommandMetadata.new(short_string: 'sa', long_string: 'same_attrs')
    allow(cli).to receive_messages(model: model, interactive_mode: true)

    bound_command = command_class.new(metadata: command_metadata).bind(cli)

    expect(bound_command.model).to eq(model)
    expect(bound_command.interactive_mode).to be(true)
  end

  it 'binds mapped attributes from differently named cli readers' do
    command_class = Class.new(described_class) do
      binds output: :out_stream
    end

    output = StringIO.new
    command_metadata = WifiWand::CommandMetadata.new(short_string: 'ma', long_string: 'mapped_attrs')
    allow(cli).to receive(:out_stream).and_return(output)

    bound_command = command_class.new(metadata: command_metadata).bind(cli)

    expect(bound_command.output).to eq(output)
  end

  it 'inherits binding declarations in subclasses' do
    parent_class = Class.new(described_class) do
      binds :model
    end

    child_class = Class.new(parent_class) do
      binds output: :out_stream
    end

    model = double('model')
    output = StringIO.new
    command_metadata = WifiWand::CommandMetadata.new(short_string: 'ca', long_string: 'child_attrs')
    allow(cli).to receive_messages(model: model, out_stream: output)

    bound_command = child_class.new(metadata: command_metadata).bind(cli)

    expect(bound_command.model).to eq(model)
    expect(bound_command.output).to eq(output)
  end
end

describe WifiWand::CommandLineInterface::CommandRegistry do
  subject { test_class.new }

  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::CommandRegistry

      def method_missing(method_name, *args) = method_name.to_s.start_with?('cmd_') ? nil : super

      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.start_with?('cmd_') || super
      end

      def model = nil

      def interactive_mode? = false

      alias_method :interactive_mode, :interactive_mode?

      def verbose_mode? = false

      alias_method :verbose_mode, :verbose_mode?

      def out_stream = StringIO.new
    end
  end

  describe '#commands' do
    it 'memoizes the commands array' do
      subject.instance_variable_set(:@commands, nil)

      first_result = subject.commands
      second_result = subject.commands

      expect(first_result).to equal(second_result)
    end

    it 'creates command objects with metadata and aliases' do
      subject.commands.each do |command|
        expect(command).to respond_to(:metadata)
        expect(command).to respond_to(:aliases)
        expect(command.metadata.short_string).to be_a(String)
        expect(command.metadata.short_string).not_to be_empty
        expect(command.metadata.long_string).to be_a(String)
        expect(command.metadata.long_string).not_to be_empty
      end
    end
  end

  describe '#find_command_action' do
    it 'returns a bound command object for a known command' do
      command = subject.resolve_command('log')

      expect(command).to be_a(WifiWand::LogCommand)
      expect(command.help_text).to include('Usage: wifi-wand log')
    end

    it 'matches the exact short command' do
      expect(subject.find_command_action('co')).to respond_to(:call)
    end

    it 'matches the exact long command' do
      expect(subject.find_command_action('connect')).to respond_to(:call)
    end

    it 'does not match intermediate partial command names' do
      expect(subject.find_command_action('con')).to be_nil
      expect(subject.find_command_action('conn')).to be_nil
      expect(subject.find_command_action('connec')).to be_nil
    end

    it 'returns nil for unrelated invalid commands' do
      expect(subject.find_command_action('unknown_command')).to be_nil
    end
  end
end
