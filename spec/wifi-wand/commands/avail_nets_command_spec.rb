# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/avail_nets_command'

describe WifiWand::AvailNetsCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand avail_nets',
    description: 'descending signal-strength order'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes available network output through handle_output' do
      allow(mock_model).to receive(:available_network_names).and_return(%w[TestNet1 TestNet2])
      allow(cli).to receive(:format_object).with(%w[TestNet1 TestNet2]).and_return("TestNet1\nTestNet2")
      expect(cli).to receive(:handle_output) do |info, producer|
        expect(info).to eq(%w[TestNet1 TestNet2])
        rendered = producer.call
        expect(rendered).to include('Available networks, in descending signal strength order')
        expect(rendered).to include('TestNet1')
        expect(rendered).to include('TestNet2')
      end

      command.call
    end

    it 'uses the empty-available-networks message when the scan is empty' do
      allow(mock_model).to receive(:available_network_names).and_return([])
      allow(cli).to receive(:empty_available_networks_message).and_return('No visible networks were found.')
      expect(cli).to receive(:handle_output) do |info, producer|
        expect(info).to eq([])
        expect(producer.call).to eq('No visible networks were found.')
      end

      command.call
    end

    it 'routes model errors through handle_output' do
      allow(mock_model).to receive(:available_network_names)
        .and_raise(WifiWand::Error.new('WiFi is off, cannot scan for available networks.'))
      expect(cli).to receive(:handle_output) do |info, producer|
        expect(info).to be_nil
        expect(producer.call).to eq('WiFi is off, cannot scan for available networks.')
      end

      command.call
    end
  end
end
