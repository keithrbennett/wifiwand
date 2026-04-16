# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/command_registry'

describe WifiWand::CommandLineInterface::CommandRegistry::Command do
  it 'has proper structure with short_string, long_string, and callable action' do
    command = described_class.new('t', 'test_command', -> { 'test' })

    expect(command.short_string).to eq('t')
    expect(command.long_string).to eq('test_command')
    expect(command.action).to respond_to(:call)
    expect(command.action.call).to eq('test')
  end
end

describe WifiWand::CommandLineInterface::CommandRegistry do
  subject { test_class.new }

  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::CommandRegistry

      def method_missing(method_name, *args) = method_name.to_s.start_with?('cmd_') ? nil : super
    end
  end

  describe '#commands' do
    it 'memoizes the commands array' do
      subject.instance_variable_set(:@commands, nil)

      first_result = subject.commands
      second_result = subject.commands

      expect(first_result).to equal(second_result)
    end

    it 'creates commands with callable actions and explicit aliases' do
      subject.commands.each do |cmd|
        expect(cmd.short_string).to be_a(String)
        expect(cmd.short_string).not_to be_empty
        expect(cmd.long_string).to be_a(String)
        expect(cmd.long_string).not_to be_empty
        expect(cmd.action).to respond_to(:call)

        begin
          cmd.action.call
        rescue
          nil
        end
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
