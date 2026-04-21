# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/forget_command'

describe WifiWand::ForgetCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand forget <name1> [name2 ...]',
    description: 'remove one or more preferred (saved) WiFi networks'

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
