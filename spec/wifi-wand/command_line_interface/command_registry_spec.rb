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

  it 'binds context and delegates calls through the bound command instance' do
    command = described_class.new(metadata: metadata, handler_name: :cmd_test)
    allow(cli).to receive(:cmd_test).with('arg').and_return('result')

    bound_command = command.bind(cli)

    expect(bound_command.metadata).to eq(metadata)
    expect(bound_command.call('arg')).to eq('result')
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
