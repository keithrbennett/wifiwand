# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/pref_nets_command'

describe WifiWand::PrefNetsCommand do
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

      expect(help).to include('Usage: wifi-wand pref_nets')
      expect(help).to include('preferred (saved) WiFi networks')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes preferred networks through handle_output' do
      allow(mock_model).to receive(:preferred_networks).and_return(%w[Network1 Network2])
      allow(cli).to receive(:format_object).with(%w[Network1 Network2]).and_return("Network1\nNetwork2")
      expect(cli).to receive(:handle_output) do |networks, producer|
        expect(networks).to eq(%w[Network1 Network2])
        rendered = producer.call
        expect(rendered).to include('Network1')
        expect(rendered).to include('Network2')
      end

      command.call
    end
  end
end
