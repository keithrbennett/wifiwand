# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/password'

describe WifiWand::Commands::Password do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:cli) do
    double(
      'cli',
      model:          mock_model,
      output_support: output_support,
      help_hint:      "Use 'wifiwand help' or 'wifiwand -h' for help."
    )
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand password <network-name>',
    description: 'stored password for a preferred WiFi network'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes the stored password through handle_output' do
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return('secret123')
      expect(output_support).to receive(:handle_output) do |password, producer|
        expect(password).to eq('secret123')
        rendered = producer.call
        expect(rendered).to include('Preferred network "TestNetwork"')
        expect(rendered).to include('stored password is "secret123"')
      end

      command.call('TestNetwork')
    end

    it 'raises a usage-oriented error when the network argument is missing' do
      expect(mock_model).not_to receive(:preferred_network_password)

      expect { command.call }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <network-name> argument.')
        expect(error.message).to include('Usage: wifiwand password <network-name>')
        expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
      }
    end

    it 'raises a usage-oriented error when the network argument is empty' do
      expect(mock_model).not_to receive(:preferred_network_password)

      expect { command.call('') }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <network-name> argument.')
        expect(error.message).to include('Usage: wifiwand password <network-name>')
        expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
      }
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:preferred_network_password)

      expect { command.call('TestNetwork', 'extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand password <network-name>')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end

    it 'routes the no-password message through handle_output' do
      allow(mock_model).to receive(:preferred_network_password).with('TestNetwork').and_return(nil)
      expect(output_support).to receive(:handle_output) do |password, producer|
        expect(password).to be_nil
        expect(producer.call).to include('has no stored password.')
      end

      command.call('TestNetwork')
    end
  end
end
