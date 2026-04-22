# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/pref_nets_command'

describe WifiWand::PrefNetsCommand do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support)
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand pref_nets',
    description: 'preferred (saved) WiFi networks'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes preferred networks through handle_output' do
      allow(mock_model).to receive(:preferred_networks).and_return(%w[Network1 Network2])
      allow(output_support).to receive(:format_object)
        .with(%w[Network1 Network2])
        .and_return("Network1\nNetwork2")
      expect(output_support).to receive(:handle_output) do |networks, producer|
        expect(networks).to eq(%w[Network1 Network2])
        rendered = producer.call
        expect(rendered).to include('Network1')
        expect(rendered).to include('Network2')
      end

      command.call
    end
  end
end
