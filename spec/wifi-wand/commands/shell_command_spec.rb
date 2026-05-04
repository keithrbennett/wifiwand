# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/shell_command'

describe WifiWand::ShellCommand do
  let(:options) { WifiWand::CommandLineOptions.new(post_processor: nil) }
  let(:cli) { double('cli', options: options) }

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

    it 'rejects trailing shell startup arguments explicitly' do
      command = described_class.new.bind(cli)

      expect(cli).not_to receive(:with_interactive_mode)
      expect(cli).not_to receive(:run_shell)

      expect do
        command.call('--help')
      end.to raise_error(
        WifiWand::ConfigurationError,
        'The shell command does not accept arguments. Received: ["--help"]'
      )
    end
  end
end
