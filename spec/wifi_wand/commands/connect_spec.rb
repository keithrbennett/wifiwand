# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/connect'

describe WifiWand::Commands::Connect do
  let(:mock_model) { double('Model') }
  let(:output) { StringIO.new }
  let(:cli) do
    double(
      'cli',
      model:            mock_model,
      interactive_mode: false,
      out_stream:       output,
      help_hint:        "Use 'wifiwand help' or 'wifiwand -h' for help."
    )
  end

  it_behaves_like 'binds command context',
    bound_attributes: { model: :mock_model, output: :output, interactive_mode: -> { false } }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand connect <network> [password]',
    description: 'connect to a WiFi network'

  describe '#validate_options' do
    subject(:command) { described_class.new }

    it 'rejects utc configuration' do
      options = WifiWand::CommandLineOptions.new(utc: false, specified_invocation_options: [:utc])

      errors = command.validate_options(
        invocation_options: options,
        command_options:    {},
        args:               ['TestNetwork']
      )

      expect(errors).to eq(['--utc is not valid for connect.'])
    end

    it 'rejects output formatting' do
      options = WifiWand::CommandLineOptions.new(specified_invocation_options: [:output_format])

      errors = command.validate_options(
        invocation_options: options,
        command_options:    {},
        args:               ['TestNetwork']
      )

      expect(errors).to eq(['--output-format is not valid for connect.'])
    end

    it 'accepts wifi interface configuration' do
      options = WifiWand::CommandLineOptions.new(
        wifi_interface:               'en0',
        specified_invocation_options: [:wifi_interface]
      )

      errors = command.validate_options(
        invocation_options: options,
        command_options:    {},
        args:               ['TestNetwork']
      )

      expect(errors).to eq([])
    end

    it 'accepts absent utc configuration' do
      options = WifiWand::CommandLineOptions.new

      errors = command.validate_options(
        invocation_options: options,
        command_options:    {},
        args:               ['TestNetwork']
      )

      expect(errors).to eq([])
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

    it 'raises a usage-oriented error when the network argument is missing' do
      expect(mock_model).not_to receive(:connect)

      expect { command.call }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <network> argument.')
        expect(error.message).to include('Usage: wifiwand connect <network> [password]')
        expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
      }
    end

    it 'raises a usage-oriented error when the network argument is empty' do
      expect(mock_model).not_to receive(:connect)

      expect { command.call('') }.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('Missing <network> argument.')
        expect(error.message).to include('Usage: wifiwand connect <network> [password]')
        expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
      }
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:connect)

      expect { command.call('TestNetwork', 'secret', 'extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand connect <network> [password]')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
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
