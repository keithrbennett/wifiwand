# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/ci_command'

describe WifiWand::CiCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode)
  end
  let(:interactive_mode) { false }

  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.model).to eq(mock_model)
      expect(bound_command.cli).to eq(cli)
      expect(bound_command.interactive_mode).to be(false)
    end
  end

  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand ci')
      expect(help).to include('Internet connectivity state')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes non-interactive output through handle_output with a string value' do
      allow(mock_model).to receive(:internet_connectivity_state).and_return(:reachable)

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to eq('reachable')
        expect(producer.call).to eq('Internet connectivity: reachable')
      end

      command.call
    end

    context 'when interactive' do
      let(:interactive_mode) { true }

      it 'routes the raw symbol through handle_output' do
        allow(mock_model).to receive(:internet_connectivity_state).and_return(:indeterminate)

        expect(cli).to receive(:handle_output) do |value, producer|
          expect(value).to eq(:indeterminate)
          expect(producer.call).to eq('Internet connectivity: indeterminate')
        end

        command.call
      end
    end
  end
end
