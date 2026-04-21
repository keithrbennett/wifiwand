# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/network_name_command'

describe WifiWand::NetworkNameCommand do
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

      expect(help).to include('Usage: wifi-wand network_name')
      expect(help).to include('currently connected WiFi network')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes the current network name through handle_output' do
      allow(mock_model).to receive(:connected_network_name).and_return('MyNetwork')
      expect(cli).to receive(:handle_output) do |name, producer|
        expect(name).to eq('MyNetwork')
        expect(producer.call).to include('MyNetwork')
      end

      command.call
    end

    it 'routes model errors through handle_output' do
      allow(mock_model).to receive(:connected_network_name).and_raise(WifiWand::Error.new('network error'))
      expect(cli).to receive(:handle_output) do |name, producer|
        expect(name).to be_nil
        expect(producer.call).to eq('network error')
      end

      command.call
    end
  end
end
