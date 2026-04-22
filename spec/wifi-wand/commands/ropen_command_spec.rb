# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/ropen_command'

describe WifiWand::RopenCommand do
  let(:mock_model) { double('Model') }
  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }
  let(:resource_manager) { double('ResourceManager') }
  let(:interactive_mode) { false }
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, out_stream: out_stream,
      err_stream: err_stream)
  end

  before do
    allow(mock_model).to receive(:resource_manager).and_return(resource_manager)
  end

  it_behaves_like 'binds command context',
    bound_attributes: {
      model:            :mock_model,
      cli:              :cli,
      interactive_mode: :interactive_mode,
      out_stream:       :out_stream,
      err_stream:       :err_stream,
    }

  describe '#help_text' do
    it 'includes usage and description without a bound model' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand ropen')
      expect(help).to include('open web resources')
    end

    it 'includes available resource help when bound' do
      allow(mock_model).to receive(:available_resources_help).and_return('Available resources help text')

      help = described_class.new.bind(cli).help_text

      expect(help).to include('Available resources help text')
    end
  end

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    context 'with no resource codes' do
      before do
        allow(mock_model).to receive(:available_resources_help).and_return('Available resources help text')
      end

      it 'prints help in non-interactive mode' do
        command.call

        expect(out_stream.string).to eq("Available resources help text\n")
      end

      context 'when interactive' do
        let(:interactive_mode) { true }

        it 'returns help text directly' do
          expect(command.call).to eq('Available resources help text')
          expect(out_stream.string).to eq('')
        end
      end
    end

    context 'with resource codes' do
      it 'opens resources and returns nil' do
        allow(mock_model).to receive(:open_resources_by_codes).with('ipw', 'spe')
          .and_return({ opened_resources: [], invalid_codes: [] })

        expect(command.call('ipw', 'spe')).to be_nil
      end

      it 'prints invalid code errors to stderr' do
        allow(mock_model).to receive(:open_resources_by_codes).with('bad')
          .and_return({ opened_resources: [], invalid_codes: ['bad'] })
        allow(resource_manager).to receive(:invalid_codes_error).with(['bad'])
          .and_return("Invalid resource code: 'bad'")

        command.call('bad')

        expect(err_stream.string).to eq("Invalid resource code: 'bad'\n")
      end
    end
  end
end
