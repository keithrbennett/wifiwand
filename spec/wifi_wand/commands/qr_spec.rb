# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/qr'

describe WifiWand::Commands::Qr do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:in_stream) { StringIO.new }
  let(:interactive_mode) { false }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, in_stream: in_stream,
      output_support: output_support, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: {
      model:            :mock_model,
      output_support:   :output_support,
      interactive_mode: :interactive_mode,
      in_stream:        :in_stream,
    }

  describe '#help_text' do
    it 'includes usage and destination guidance' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand qr')
      expect(help).to include('Default output prints an ANSI QR to stdout')
      expect(help).to include('Pass a filename to write a QR image file')
      expect(help).to include('Supported file extensions are .png, .svg, and .eps')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes file output through handle_output' do
      allow(mock_model).to receive(:generate_qr_code)
        .with('test.png', password: nil, in_stream: in_stream).and_return('test.png')

      expect(output_support).to receive(:handle_output) do |value, producer|
        expect(value).to eq('test.png')
        expect(producer.call).to eq('QR code generated: test.png')
      end

      command.call('test.png')
    end

    it 'prints to stdout by default in non-interactive mode' do
      expect(mock_model).to receive(:print_qr_code)
        .with(password: nil).and_return(nil)

      expect(command.call).to be_nil
    end

    it 'returns nil when explicitly printing to stdout in non-interactive mode' do
      expect(mock_model).to receive(:print_qr_code)
        .with(password: nil).and_return(nil)

      expect(command.call('-')).to be_nil
    end

    it 'uses hyphen as an explicit stdout target when a password is passed' do
      expect(mock_model).to receive(:print_qr_code)
        .with(password: 'secret').and_return(nil)

      expect(command.call('-', 'secret')).to be_nil
    end

    it 'treats an empty filespec as stdout output' do
      expect(mock_model).to receive(:print_qr_code)
        .with(password: nil).and_return(nil)

      expect(command.call('')).to be_nil
    end

    it 'rejects output formatting for stdout output' do
      options = WifiWand::CommandLineOptions.new(
        post_processor:               ->(object) { object.inspect },
        invocation_option_sources:    { output_format: :command_line },
        specified_invocation_options: [:output_format]
      )
      output_support = double('output_support', options: options)
      cli = double('cli', model: mock_model, interactive_mode: false, in_stream: in_stream,
        output_support: output_support, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      command = described_class.new.bind(cli)

      expect(mock_model).not_to receive(:print_qr_code)
      expect { command.call }.to raise_error(WifiWand::ConfigurationError, /qr stdout output/)
    end

    it 'ignores an implicit post processor when output formatting was not specified' do
      options = WifiWand::CommandLineOptions.new(
        post_processor: ->(object) { object.inspect }
      )
      output_support = double('output_support', options: options)
      cli = double('cli', model: mock_model, interactive_mode: false, in_stream: in_stream,
        output_support: output_support, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      command = described_class.new.bind(cli)

      expect(mock_model).to receive(:print_qr_code)
        .with(password: nil).and_return(nil)

      expect(command.call).to be_nil
    end

    it 'ignores environment-sourced output formatting for stdout output at runtime' do
      options = WifiWand::CommandLineOptions.new(
        post_processor:               ->(object) { object.inspect },
        invocation_option_sources:    { output_format: :environment },
        specified_invocation_options: [:output_format]
      )
      output_support = double('output_support', options: options)
      cli = double('cli', model: mock_model, interactive_mode: false, in_stream: in_stream,
        output_support: output_support, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
      command = described_class.new.bind(cli)

      expect(mock_model).to receive(:print_qr_code)
        .with(password: nil).and_return(nil)

      expect(command.call).to be_nil
    end

    context 'when interactive and printing to stdout' do
      let(:interactive_mode) { true }

      it 'prints the ANSI QR and returns a silent shell result' do
        allow(mock_model).to receive(:print_qr_code)
          .with(password: nil).and_return(nil)

        expect(command.call).to equal(WifiWand::Commands::SILENT_RESULT)
      end
    end

    context 'when the generator reports an existing output file' do
      let(:error) { WifiWand::Error.new('File test.png already exists') }

      it 'lets the generator own overwrite confirmation' do
        allow(mock_model).to receive(:generate_qr_code)
          .with('test.png', password: nil, in_stream: in_stream).and_raise(error)

        expect { command.call('test.png') }
          .to raise_error(WifiWand::Error, 'File test.png already exists')
      end
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(mock_model).not_to receive(:generate_qr_code)

      expect { command.call('test.png', 'secret', 'extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifi-wand qr [filespec] [password]')
          expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
        }
    end
  end

  describe '#validate_options' do
    subject(:command) { described_class.new }

    it 'rejects output formatting for default stdout output' do
      options = WifiWand::CommandLineOptions.new(
        specified_invocation_options: [:output_format],
        invocation_option_sources:    { output_format: :command_line }
      )

      errors = command.validate_options(invocation_options: options, command_options: {}, args: [])

      expect(errors).to eq([
        '--output-format is not valid for qr stdout output. Pass a filename for formatted file output.',
      ])
    end

    it 'rejects output formatting for explicit stdout output' do
      options = WifiWand::CommandLineOptions.new(
        specified_invocation_options: [:output_format],
        invocation_option_sources:    { output_format: :command_line }
      )

      errors = command.validate_options(invocation_options: options, command_options: {}, args: ['-'])

      expect(errors).to eq([
        '--output-format is not valid for qr stdout output. Pass a filename for formatted file output.',
      ])
    end

    it 'ignores environment-sourced output formatting for stdout output' do
      options = WifiWand::CommandLineOptions.new(
        specified_invocation_options: [:output_format],
        invocation_option_sources:    { output_format: :environment }
      )

      errors = command.validate_options(invocation_options: options, command_options: {}, args: [])

      expect(errors).to eq([])
    end

    it 'accepts output formatting for file output' do
      options = WifiWand::CommandLineOptions.new(
        specified_invocation_options: [:output_format],
        invocation_option_sources:    { output_format: :command_line }
      )

      errors = command.validate_options(invocation_options: options, command_options: {}, args: ['wifi.png'])

      expect(errors).to eq([])
    end
  end
end
