# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/shell'

describe WifiWand::Commands::Shell do
  let(:options) { WifiWand::CommandLineOptions.new(post_processor: nil) }
  let(:cli) do
    double('cli', options: options, help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.")
  end

  it_behaves_like 'binds command context', bound_attributes: {}

  describe '#call' do
    it 'runs the existing shell entry path inside interactive mode' do
      command = described_class.new.bind(cli)

      expect(cli).to receive(:with_interactive_mode).and_yield
      expect(cli).to receive(:run_shell)

      command.call
    end

    it 'rejects output formatting for shell startup' do
      options.post_processor = ->(object) { object.to_json }
      command = described_class.new.bind(cli)

      expect(cli).not_to receive(:with_interactive_mode)
      expect(cli).not_to receive(:run_shell)

      expect do
        command.call
      end.to raise_error(
        WifiWand::ConfigurationError,
        'Output formatting is not supported for the shell command.'
      )
    end

    it 'ignores environment-sourced output formatting for shell startup' do
      options.post_processor = ->(object) { object.to_json }
      options.invocation_option_sources = { output_format: :environment }
      command = described_class.new.bind(cli)

      expect(cli).to receive(:with_interactive_mode).and_yield
      expect(cli).to receive(:run_shell)

      command.call
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      command = described_class.new.bind(cli)

      expect(cli).not_to receive(:with_interactive_mode)
      expect(cli).not_to receive(:run_shell)

      expect { command.call('--help') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): --help')
          expect(error.message).to include('Usage: wifi-wand shell')
          expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
        }
    end
  end
end
