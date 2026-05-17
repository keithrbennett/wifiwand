# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/command_line_interface'

describe WifiWand::Commands::OutputSupport do
  include TestHelpers

  let(:mock_model) { create_standard_mock_model }
  let(:mock_os) { create_mock_os_with_model(mock_model) }
  let(:options) { create_cli_options }
  let(:interactive_options) { create_cli_options(interactive_mode: true) }
  let(:cli) { WifiWand::CommandLineInterface.new(options) }
  let(:interactive_cli) { WifiWand::CommandLineInterface.new(interactive_options) }

  before do
    allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(mock_os)
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

    it 'applies utc display conversion before post processing Time values' do
      timestamp = Time.new(2026, 5, 17, 18, 3, 50, '+07:00')
      json_options = create_cli_options(post_processor: ->(obj) { JSON.generate(obj) }, utc: true)
      json_cli = WifiWand::CommandLineInterface.new(json_options)
      output_support = described_class.new(json_cli)
      output = nil

      silence_output do |stdout, _stderr|
        output_support.handle_output({ timestamp: timestamp }, human_readable_producer)
        output = stdout.string
      end

      expect(JSON.parse(output)).to eq('timestamp' => '2026-05-17T11:03:50Z')
      expect(timestamp.utc_offset).to eq(7 * 60 * 60)
    end

    it 'applies local display conversion before post processing Time values by default' do
      previous_tz = ENV.fetch('TZ', nil)
      ENV['TZ'] = 'America/New_York'
      timestamp = Time.utc(2026, 5, 17, 11, 3, 50)
      json_options = create_cli_options(post_processor: ->(obj) { JSON.generate(obj) })
      json_cli = WifiWand::CommandLineInterface.new(json_options)
      output_support = described_class.new(json_cli)
      output = nil

      silence_output do |stdout, _stderr|
        output_support.handle_output({ timestamp: timestamp }, human_readable_producer)
        output = stdout.string
      end

      expect(JSON.parse(output)).to eq('timestamp' => timestamp.getlocal.iso8601)
      expect(timestamp).to be_utc
    ensure
      previous_tz.nil? ? ENV.delete('TZ') : ENV['TZ'] = previous_tz
    end

    it 'uses the human readable producer when no post processor is configured' do
      output_support = described_class.new(cli)

      expect do
        output_support.handle_output(test_data, human_readable_producer)
      end.to output("Human readable output\n").to_stdout
    end
  end

  describe '#display_width' do
    it 'counts ANSI-free ASCII text by character length' do
      output_support = described_class.new(cli)

      expect(output_support.display_width('WiFi: WAIT')).to eq('WiFi: WAIT'.length)
    end

    it 'counts status emoji by terminal cell width after stripping ANSI color' do
      output_support = described_class.new(cli)

      expect(output_support.display_width("\e[33m⏳ WAIT\e[0m")).to eq(7)
      expect(output_support.display_width('✅ ON')).to eq(5)
    end
  end
end
