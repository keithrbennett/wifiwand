# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/ci_command'

describe WifiWand::CiCommand do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, output_support: output_support)
  end
  let(:interactive_mode) { false }

  it_behaves_like 'binds command context',
    bound_attributes: {
      model: :mock_model, output_support: :output_support, interactive_mode: :interactive_mode
    }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand ci',
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
  end
end
