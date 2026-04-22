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

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output: :output, interactive_mode: -> { false } }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand connect <network> [password]',
    description: 'connect to a WiFi network'

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
