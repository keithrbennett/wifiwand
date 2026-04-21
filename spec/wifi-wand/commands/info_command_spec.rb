# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/info_command'

describe WifiWand::InfoCommand do
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

      expect(help).to include('Usage: wifi-wand info')
      expect(help).to include('detailed networking information')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi info through handle_output using the formatter path' do
      info = { 'status' => 'connected' }
      allow(mock_model).to receive(:wifi_info).and_return(info)
      allow(cli).to receive(:format_object).with(info).and_return('formatted info')

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to eq(info)
        expect(producer.call).to eq('formatted info')
      end

      command.call
    end
  end
end
