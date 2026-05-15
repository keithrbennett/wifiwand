# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/info'

describe WifiWand::Commands::Info do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support,
      help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand info',
    description: 'detailed networking information'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi info through handle_output using the formatter path' do
      info = { 'status' => 'connected' }
      allow(mock_model).to receive(:wifi_info).and_return(info)
      allow(output_support).to receive(:format_object).with(info).and_return('formatted info')

      expect(output_support).to receive(:handle_output) do |value, producer|
        expect(value).to eq(info)
        expect(producer.call).to eq('formatted info')
      end

      command.call
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:wifi_info)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifi-wand info')
          expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
        }
    end
  end
end
