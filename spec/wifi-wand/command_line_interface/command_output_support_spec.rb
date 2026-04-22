# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface'

describe WifiWand::CommandLineInterface::CommandOutputSupport do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:interactive_options) { create_cli_options(interactive_mode: true) }
  let(:cli) { WifiWand::CommandLineInterface.new(options) }
  let(:interactive_cli) { WifiWand::CommandLineInterface.new(interactive_options) }

  before do
    allow(WifiWand::OperatingSystems).to receive(:current_os).and_return(mock_os)
  end

  describe '#handle_output' do
    let(:test_data) { { key: 'value' } }
    let(:human_readable_producer) { -> { 'Human readable output' } }
    let(:processor) { ->(obj) { obj.to_s.upcase } }
    let(:options_with_processor) { create_cli_options(post_processor: processor) }
    let(:cli_with_processor) { WifiWand::CommandLineInterface.new(options_with_processor) }

    it 'returns data directly in interactive mode' do
      output_support = described_class.new(interactive_cli)

      result = output_support.handle_output(test_data, human_readable_producer)
      expect(result).to eq(test_data)
    end

    it 'uses the post processor when configured' do
      output_support = described_class.new(cli_with_processor)
      output = nil

      silence_output do |stdout, _stderr|
        output_support.handle_output(test_data, human_readable_producer)
        output = stdout.string
      end

      expect(output).to eq(%({:KEY=>"VALUE"}\n)).or eq(%({KEY: "VALUE"}\n))
    end

    it 'uses the human readable producer when no post processor is configured' do
      output_support = described_class.new(cli)

      expect do
        output_support.handle_output(test_data, human_readable_producer)
      end.to output("Human readable output\n").to_stdout
    end
  end
end
