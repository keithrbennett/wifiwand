# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/connect_command'

describe WifiWand::ConnectCommand do
  let(:mock_model) { double('Model') }
  let(:output) { StringIO.new }
  let(:cli) do
    double(
      'cli',
      model:            mock_model,
      interactive_mode: false,
      out_stream:       output
    )
  end

  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.model).to eq(mock_model)
      expect(bound_command.output).to eq(output)
      expect(bound_command.interactive_mode).to be(false)
    end
  end

  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand connect <network> [password]')
      expect(help).to include('connect to a WiFi network')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    before do
      allow(mock_model).to receive(:connect)
    end

    it 'connects with a provided password' do
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(false)

      command.call('TestNetwork', 'secret')

      expect(mock_model).to have_received(:connect).with('TestNetwork', 'secret')
      expect(output.string).to eq('')
    end

    it 'shows a saved-password message in non-interactive mode' do
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(true)

      command.call('SavedNetwork')

      expect(mock_model).to have_received(:connect).with('SavedNetwork', nil)
      expect(output.string).to include("Using saved password for 'SavedNetwork'.")
    end

    it 'does not show a saved-password message when the password was explicit' do
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(false)

      command.call('TestNetwork', 'secret')

      expect(output.string).to eq('')
    end

    it 'does not show a saved-password message in interactive mode' do
      interactive_command = described_class.new(
        model:            mock_model,
        output:           output,
        interactive_mode: true
      )
      allow(mock_model).to receive(:last_connection_used_saved_password?).and_return(true)

      interactive_command.call('SavedNetwork')

      expect(output.string).to eq('')
    end
  end
end
