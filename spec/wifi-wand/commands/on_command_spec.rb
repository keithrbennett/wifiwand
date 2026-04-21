# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/on_command'

describe WifiWand::OnCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand on',
    description: 'turn WiFi on'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'delegates to model.wifi_on' do
      expect(mock_model).to receive(:wifi_on)

      command.call
    end
  end
end
