# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/disconnect_command'

describe WifiWand::DisconnectCommand do
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
    end
  end

  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand disconnect')
      expect(help).to include('disconnect from the current WiFi network')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'delegates to model.disconnect' do
      expect(mock_model).to receive(:disconnect)

      command.call
    end
  end
end
