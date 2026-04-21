# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/nameservers_command'

describe WifiWand::NameserversCommand do
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

      expect(help).to include('Usage: wifi-wand nameservers [get|clear|IP ...]')
      expect(help).to include('show, clear, or set DNS nameservers')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes current nameservers through handle_output when no args are provided' do
      allow(mock_model).to receive(:nameservers).and_return(['8.8.8.8', '1.1.1.1'])
      expect(cli).to receive(:handle_output) do |nameservers, producer|
        expect(nameservers).to eq(['8.8.8.8', '1.1.1.1'])
        expect(producer.call).to eq('Nameservers: 8.8.8.8, 1.1.1.1')
      end

      command.call
    end

    it 'routes current nameservers through handle_output for explicit get' do
      allow(mock_model).to receive(:nameservers).and_return(['8.8.8.8'])
      expect(cli).to receive(:handle_output) do |nameservers, producer|
        expect(nameservers).to eq(['8.8.8.8'])
        expect(producer.call).to eq('Nameservers: 8.8.8.8')
      end

      command.call('get')
    end

    it 'shows [None] when there are no nameservers' do
      allow(mock_model).to receive(:nameservers).and_return([])
      expect(cli).to receive(:handle_output) do |nameservers, producer|
        expect(nameservers).to eq([])
        expect(producer.call).to eq('Nameservers: [None]')
      end

      command.call
    end

    it 'clears nameservers when asked' do
      expect(mock_model).to receive(:set_nameservers).with(:clear)

      command.call('clear')
    end

    it 'sets provided nameservers' do
      expect(mock_model).to receive(:set_nameservers).with(['9.9.9.9', '8.8.4.4'])

      command.call('9.9.9.9', '8.8.4.4')
    end
  end
end
