# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/ci'

describe WifiWand::Commands::Ci do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, output_support: output_support,
      help_hint: "Use 'wifiwand help' or 'wifiwand -h' for help.")
  end
  let(:interactive_mode) { false }

  it_behaves_like 'binds command context',
    bound_attributes: {
      model: :mock_model, output_support: :output_support, interactive_mode: :interactive_mode
    }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand ci',
    description: 'Internet connectivity state'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes non-interactive output through handle_output with a string value' do
      allow(mock_model).to receive(:internet_connectivity_state).and_return(:reachable)

      expect(output_support).to receive(:handle_output) do |value, producer|
        expect(value).to eq('reachable')
        expect(producer.call).to eq('Internet connectivity: reachable')
      end

      command.call
    end

    context 'when interactive' do
      let(:interactive_mode) { true }

      it 'routes the raw symbol through handle_output' do
        allow(mock_model).to receive(:internet_connectivity_state).and_return(:indeterminate)

        expect(output_support).to receive(:handle_output) do |value, producer|
          expect(value).to eq(:indeterminate)
          expect(producer.call).to eq('Internet connectivity: indeterminate')
        end

        command.call
      end
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:internet_connectivity_state)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand ci')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end
  end
end
