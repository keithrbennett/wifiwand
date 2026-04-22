# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/status_command'

describe WifiWand::StatusCommand do
  let(:mock_model) { double('Model') }
  let(:out_stream) { StringIO.new }
  let(:interactive_mode) { false }
  let(:output_support_class) do
    Class.new do
      attr_reader :handled

      def initialize(progress_mode:, rendered_status: 'rendered')
        @progress_mode = progress_mode
        @rendered_status = rendered_status
        @handled = nil
      end

      def status_line(data)
        data.nil? ? '[status unavailable]' : @rendered_status
      end

      def handle_output(data, producer)
        @handled = [data, producer.call]
      end

      def status_progress_mode = @progress_mode

      def strip_ansi(text) = text.to_s
    end
  end
  let(:output_support) do
    output_support_class.new(progress_mode: progress_mode, rendered_status: rendered_status)
  end
  let(:cli) do
    double('cli', model: mock_model, interactive_mode: interactive_mode, out_stream: out_stream,
      output_support: output_support)
  end
  let(:progress_mode) { :none }
  let(:rendered_status) { 'WiFi: ON | Network: "TestNet"' }

  it_behaves_like 'binds command context',
    bound_attributes: {
      model:            :mock_model,
      output_support:   :output_support,
      interactive_mode: :interactive_mode,
      out_stream:       :out_stream,
    }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand status',
    description: 'status line'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    let(:status_data) { { wifi_on: true, internet_state: :reachable } }

    before do
      allow(mock_model).to receive(:status_line_data).and_return(status_data)
    end

    it 'returns structured data in non-interactive mode when progress is disabled' do
      result = command.call

      expect(result).to eq(status_data)
      expect(output_support.handled).to eq([status_data, rendered_status])
    end

    context 'when interactive and progress is disabled' do
      let(:interactive_mode) { true }

      it 'prints the rendered status line and returns nil' do
        expect(command.call).to be_nil
        expect(out_stream.string).to eq("#{rendered_status}
")
      end
    end

    context 'when inline progress is enabled' do
      let(:progress_mode) { :inline }

      it 'streams in-place updates and returns structured data' do
        result = command.call

        expect(result).to eq(status_data)
        expect(out_stream.string).to include("\r#{rendered_status}")
        expect(out_stream.string).to end_with($INPUT_RECORD_SEPARATOR)
      end
    end
  end
end
