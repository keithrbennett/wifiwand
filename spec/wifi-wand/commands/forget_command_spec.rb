# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/forget_command'

describe WifiWand::ForgetCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.model).to eq(mock_model)
      expect(bound_command.cli).to eq(cli)
    end
  end

  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand forget <name1> [name2 ...]')
      expect(help).to include('remove one or more preferred (saved) WiFi networks')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes removed networks through handle_output' do
      allow(mock_model).to receive(:remove_preferred_networks).with('Network1', 'Network2')
        .and_return(['Network1', 'Network1 1'])
      expect(cli).to receive(:handle_output) do |removed_networks, producer|
        expect(removed_networks).to eq(['Network1', 'Network1 1'])
        expect(producer.call).to include('Removed networks: ["Network1", "Network1 1"]')
      end

      command.call('Network1', 'Network2')
    end
  end
end
