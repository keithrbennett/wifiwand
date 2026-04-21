# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/wifi_on_command'

describe WifiWand::WifiOnCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand wifi_on',
    description: 'is the WiFi on?'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi state through handle_output' do
      allow(mock_model).to receive(:wifi_on?).and_return(true)

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to be(true)
        expect(producer.call).to eq('Wifi on: true')
      end

      command.call
    end
  end
end
