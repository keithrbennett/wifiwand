# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/info_command'

describe WifiWand::InfoCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand info',
    description: 'detailed networking information'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes wifi info through handle_output using the formatter path' do
      info = { 'status' => 'connected' }
      allow(mock_model).to receive(:wifi_info).and_return(info)
      allow(cli).to receive(:format_object).with(info).and_return('formatted info')

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to eq(info)
        expect(producer.call).to eq('formatted info')
      end

      command.call
    end
  end
end
