# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/disconnect_command'

describe WifiWand::DisconnectCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand disconnect',
    description: 'disconnect from the current WiFi network'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'delegates to model.disconnect' do
      expect(mock_model).to receive(:disconnect)

      command.call
    end
  end
end
