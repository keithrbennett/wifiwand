# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/nameservers_command'

describe WifiWand::NameserversCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand nameservers [get|clear|IP ...]',
    description: 'show, clear, or set DNS nameservers'

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
