# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/wifi_on'

describe WifiWand::Commands::WifiOn do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support,
      help_hint: "Use 'wifiwand help' or 'wifiwand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand wifi_on',
    description: 'is the WiFi on?'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi state through handle_output' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(output_support).to receive(:handle_output) do |value, producer|
        expect(value).to be(true)
        expect(producer.call).to eq('Wifi on: true')
      end

      command.call
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:wifi_on?)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand wifi_on')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end
  end
end
