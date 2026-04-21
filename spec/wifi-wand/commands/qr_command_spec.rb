# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/qr_command'

describe WifiWand::QrCommand do
  let(:mock_model) { double('Model') }
  let(:out_stream) { StringIO.new }
  let(:in_stream) { StringIO.new }
  let(:interactive_mode) { false }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, out_stream: out_stream,
      in_stream: in_stream)
  end

  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)
      expect(bound_command.model).to eq(mock_model)
      expect(bound_command.cli).to eq(cli)
      expect(bound_command.interactive_mode).to be(false)
      expect(bound_command.out_stream).to eq(out_stream)
      expect(bound_command.in_stream).to eq(in_stream)
    end
  end

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
      allow(mock_model).to receive(:generate_qr_code).with('test.png', password: nil).and_return('test.png')

      expect(cli).to receive(:handle_output) do |value, producer|
        expect(value).to eq('test.png')
        expect(producer.call).to eq('QR code generated: test.png')
      end

      command.call('test.png')
    end

    it 'returns nil when printing to stdout in non-interactive mode' do
      allow(mock_model).to receive(:generate_qr_code)
        .with('-', hash_including(delivery_mode: :print, password: nil)).and_return('-')

      expect(command.call('-')).to be_nil
    end

    context 'when interactive and printing to stdout' do
      let(:interactive_mode) { true }

      it 'returns the ANSI QR string' do
        allow(mock_model).to receive(:generate_qr_code)
          .with('-', hash_including(delivery_mode: :return, password: nil)).and_return('[QR]')

        expect(command.call('-')).to eq('[QR]')
      end
    end

    context 'when handling overwrite confirmation' do
      let(:error) { WifiWand::Error.new('File test.png already exists') }

      before do
        allow(mock_model).to receive(:generate_qr_code).with('test.png', password: nil).and_raise(error)
        allow(in_stream).to receive(:tty?).and_return(true)
      end

      it 'retries with overwrite when the user confirms' do
        allow(in_stream).to receive(:gets).and_return('y
')
        allow(mock_model).to receive(:generate_qr_code)
          .with('test.png', overwrite: true, password: nil).and_return('test.png')

        expect(cli).to receive(:handle_output)
        command.call('test.png')
        expect(out_stream.string).to include('Output file exists. Overwrite? [y/N]: ')
      end

      it 'returns nil when the user declines overwrite' do
        allow(in_stream).to receive(:gets).and_return('n
')

        expect(command.call('test.png')).to be_nil
      end
    end
  end
end
