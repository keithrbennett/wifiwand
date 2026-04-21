# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/quit_command'

describe WifiWand::QuitCommand do
  let(:cli) { double('cli') }

  describe '#bind' do
    it 'returns a bound command with the CLI context' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.cli).to eq(cli)
    end
  end

  describe '#aliases' do
    it 'includes quit and xit aliases' do
      expect(described_class.new.aliases).to eq(%w[q quit x xit])
    end
  end

  describe '#help_text' do
    it 'includes usage, description, and xit aliases' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand quit')
      expect(help).to include('exit this program in interactive shell mode')
      expect(help).to include('Also available as: x, xit')
    end
  end

  describe '#call' do
    it 'delegates to cli.quit' do
      command = described_class.new.bind(cli)
      expect(cli).to receive(:quit)

      command.call
    end
  end
end
