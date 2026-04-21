# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/password_command'

describe WifiWand::PasswordCommand do
  let(:mock_model) { double('Model') }
  let(:cli) do
    double('cli', model: mock_model)
  end

  it_behaves_like 'binds command context', bound_attributes: { model: :mock_model, cli: :cli }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand password <network-name>',
    description: 'stored password for a preferred WiFi network'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes the stored password through handle_output' do
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('secret123')
      expect(cli).to receive(:handle_output) do |password, producer|
        expect(password).to eq('secret123')
        rendered = producer.call
        expect(rendered).to include('Preferred network "TestNetwork"')
        expect(rendered).to include('stored password is "secret123"')
      end

      command.call('TestNetwork')
    end

    it 'routes the no-password message through handle_output' do
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return(nil)
      expect(cli).to receive(:handle_output) do |password, producer|
        expect(password).to be_nil
        expect(producer.call).to include('has no stored password.')
      end

      command.call('TestNetwork')
    end
  end
end
