# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/forget_command'

describe WifiWand::ForgetCommand do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double(
      'cli',
      model:          mock_model,
      output_support: output_support,
      help_hint:      "Use 'wifi-wand help' or 'wifi-wand -h' for help."
    )
  end

  it_behaves_like 'binds command context',
    bound_attributes: { cli: :cli, model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand forget <name1> [name2 ...]',
    description: 'remove one or more preferred (saved) WiFi networks'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes removed networks through handle_output' do
      allow(mock_model).to receive(:remove_preferred_networks).with('Network1', 'Network2')
        .and_return(['Network1', 'Network1 1'])
      expect(output_support).to receive(:handle_output) do |removed_networks, producer|
        expect(removed_networks).to eq(['Network1', 'Network1 1'])
        expect(producer.call).to include('Removed networks: ["Network1", "Network1 1"]')
      end

      command.call('Network1', 'Network2')
    end

    it 'raises a usage-oriented error when no network names are provided' do
      expect(mock_model).not_to receive(:remove_preferred_networks)

      expect { command.call }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <name1> argument.')
        expect(error.message).to include('Usage: wifi-wand forget <name1> [name2 ...]')
        expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      }
    end

    it 'raises a usage-oriented error when the first network name is nil' do
      expect(mock_model).not_to receive(:remove_preferred_networks)

      expect { command.call(nil) }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <name1> argument.')
        expect(error.message).to include('Usage: wifi-wand forget <name1> [name2 ...]')
        expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      }
    end
  end
end
