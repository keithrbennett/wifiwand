# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/network_name_command'

describe WifiWand::NetworkNameCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand network_name',
    description: 'currently connected WiFi network'

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
