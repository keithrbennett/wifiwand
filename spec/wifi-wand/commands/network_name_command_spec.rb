# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/network_name_command'

describe WifiWand::NetworkNameCommand do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', model: mock_model, output_support: output_support)
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand network_name',
    description: 'currently connected WiFi network'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes the current network name through handle_output' do
      allow(mock_model).to receive(:connected_network_name).and_return('MyNetwork')
      expect(output_support).to receive(:handle_output) do |name, producer|
        expect(name).to eq('MyNetwork')
        expect(producer.call).to include('MyNetwork')
      end

      command.call
    end

    it 'propagates WiFi-off errors for CLI-level error handling' do
      allow(mock_model).to receive(:connected_network_name)
        .and_raise(WifiWand::WifiOffError.new('WiFi is off'))

      expect { command.call }.to raise_error(WifiWand::WifiOffError, 'WiFi is off')
    end

    it 'propagates exact identity errors for CLI-level error handling' do
      error = WifiWand::MacOsRedactionError.new(operation_description: 'showing the current SSID')
      allow(mock_model).to receive(:connected_network_name).and_raise(error)

      expect { command.call }.to raise_error(WifiWand::MacOsRedactionError, /Exact WiFi network identity/)
    end
  end
end
