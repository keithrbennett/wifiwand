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
        return '[status unavailable]' if data.nil?
        return @rendered_status.(data) if @rendered_status.respond_to?(:call)

        @rendered_status
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
        expect(output_support.handled).to be_nil
      end

      it 'prints unavailable status and returns nil when status data is unavailable' do
        allow(mock_model).to receive(:status_line_data).and_return(nil)

        expect(command.call).to be_nil
        expect(out_stream.string).to eq("[status unavailable]\n")
      end
    end

    context 'when inline progress is enabled' do
      let(:progress_mode) { :inline }

      it 'streams in-place updates and returns structured data' do
        result = command.call

        expect(result).to eq(status_data)
        expect(out_stream.string).to eq("#{rendered_status}\n")
      end

      it 'continues with final status data after a nil progress update' do
        allow(mock_model).to receive(:status_line_data) do |progress_callback:|
          progress_callback.call(nil)
          status_data
        end
        allow(output_support).to receive(:status_line) do |data|
          data[:wifi_on].nil? ? 'WiFi: WAIT | Network: [pending]' : rendered_status
        end
        expected_padding = ' ' * ('WiFi: WAIT | Network: [pending]'.length - rendered_status.length)
        expected_output = "WiFi: WAIT | Network: [pending]\r#{rendered_status}#{expected_padding}\n"

        result = command.call

        expect(result).to eq(status_data)
        expect(out_stream.string).to eq(expected_output)
        expect(out_stream.string).not_to include('[status unavailable]')
      end

      it 'finishes the progress line when a post-error final render is empty' do
        allow(mock_model).to receive(:status_line_data) do |progress_callback:|
          progress_callback.call(nil)
          status_data
        end
        allow(output_support).to receive(:status_line) do |data|
          data[:wifi_on].nil? ? rendered_status : ''
        end

        result = command.call

        expect(result).to eq(status_data)
        expect(out_stream.string).to eq("#{rendered_status}\n")
      end

      it 'rewrites the progress line with unavailable status when inline status data fails' do
        allow(mock_model).to receive(:status_line_data) do |progress_callback:|
          progress_callback.call(wifi_on: false, internet_state: :unreachable)
          progress_callback.call(nil)
          nil
        end
        expected_padding = ' ' * (rendered_status.length - '[status unavailable]'.length)
        expected_unavailable_line = "\r[status unavailable]#{expected_padding}#{$INPUT_RECORD_SEPARATOR}"

        expect { command.call }.to raise_error(WifiWand::StatusUnavailableError)

        expect(out_stream.string).to start_with(rendered_status)
        expect(out_stream.string).to include(expected_unavailable_line)
        expect(out_stream.string).not_to include('\r')
      end

      it 'rewrites the progress line with unavailable status when final status data is nil' do
        allow(mock_model).to receive(:status_line_data).and_return(nil)
        expected_padding = ' ' * (rendered_status.length - '[status unavailable]'.length)
        expected_unavailable_line = "\r[status unavailable]#{expected_padding}#{$INPUT_RECORD_SEPARATOR}"

        expect { command.call }.to raise_error(WifiWand::StatusUnavailableError)

        expect(out_stream.string).to start_with(rendered_status)
        expect(out_stream.string).to include(expected_unavailable_line)
      end

      context 'when interactive' do
        let(:interactive_mode) { true }

        it 'rewrites the progress line with unavailable status and returns nil' do
          allow(mock_model).to receive(:status_line_data).and_return(nil)
          expected_padding = ' ' * (rendered_status.length - '[status unavailable]'.length)
          expected_unavailable_line = "\r[status unavailable]#{expected_padding}#{$INPUT_RECORD_SEPARATOR}"

          expect(command.call).to be_nil
          expect(out_stream.string).to start_with(rendered_status)
          expect(out_stream.string).to include(expected_unavailable_line)
        end
      end

      context 'when no inline progress text is rendered' do
        let(:rendered_status) do
          ->(data) do
            data[:wifi_on].nil? ? '' : 'WiFi: ON | Network: "TestNet"'
          end
        end

        it 'prints the final status line without an in-place progress prefix' do
          result = command.call

          expect(result).to eq(status_data)
          expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
        end

        it 'prints unavailable status without an in-place progress prefix when status data fails' do
          allow(mock_model).to receive(:status_line_data).and_return(nil)

          expect { command.call }.to raise_error(WifiWand::StatusUnavailableError)

          expect(out_stream.string).to eq("[status unavailable]\n")
        end

        it 'does not prefix the first visible callback with a carriage return' do
          allow(mock_model).to receive(:status_line_data) do |progress_callback:|
            progress_callback.call(status_data)
            status_data
          end

          result = command.call

          expect(result).to eq(status_data)
          expect(out_stream.string).to eq("WiFi: ON | Network: \"TestNet\"\n")
        end
      end
    end
  end
end
