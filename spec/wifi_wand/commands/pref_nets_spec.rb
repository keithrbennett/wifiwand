# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/pref_nets'

describe WifiWand::Commands::PrefNets do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support,
      help_hint: "Use 'wifiwand help' or 'wifiwand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand pref_nets',
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

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:preferred_networks)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand pref_nets')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end
  end
end
