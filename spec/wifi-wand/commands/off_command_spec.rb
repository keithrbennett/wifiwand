# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/off_command'

describe WifiWand::OffCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand off',
    description: 'turn WiFi off'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'delegates to model.wifi_off' do
      expect(mock_model).to receive(:wifi_off)

      command.call
    end
  end
end
