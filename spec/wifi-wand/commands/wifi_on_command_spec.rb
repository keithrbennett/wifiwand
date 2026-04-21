# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/wifi_on_command'

describe WifiWand::WifiOnCommand do
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

      expect(help).to include('Usage: wifi-wand wifi_on')
      expect(help).to include('is the WiFi on?')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi state through handle_output' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to be(true)
        expect(producer.call).to eq('Wifi on: true')
      end

      command.call
    end
  end
end
