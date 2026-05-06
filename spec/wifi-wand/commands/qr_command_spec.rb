# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/qr_command'

describe WifiWand::QrCommand do
  let(:mock_model) { double('Model') }
  let(:output_support) { double('output_support') }
  let(:in_stream) { StringIO.new }
  let(:interactive_mode) { false }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, in_stream: in_stream,
      output_support: output_support)
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
      expect(help).to include('Default PNG file: <SSID>-qr-code.png')
      expect(help).to include("Use '-' to print ANSI QR to stdout")
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

    it 'returns nil when printing to stdout in non-interactive mode' do
      allow(mock_model).to receive(:generate_qr_code)
        .with('-', hash_including(
          delivery_mode: :print,
          password:      nil,
          in_stream:     in_stream
        )).and_return('-')

      expect(command.call('-')).to be_nil
    end

    context 'when interactive and printing to stdout' do
      let(:interactive_mode) { true }

      it 'returns the ANSI QR string' do
        allow(mock_model).to receive(:generate_qr_code)
          .with('-', hash_including(delivery_mode: :return, password: nil,
            in_stream: in_stream)).and_return('[QR]')

        expect(command.call('-')).to eq('[QR]')
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
  end
end
