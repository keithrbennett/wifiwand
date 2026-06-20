# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/help'

describe WifiWand::Commands::Help do
  let(:output) { StringIO.new }
  let(:cli) do
    Class.new do
      attr_reader :printed_help, :last_lookup

      attr_reader :out_stream

      def initialize
        @printed_help = false
        @out_stream = StringIO.new
      end

      def help_text = 'GLOBAL HELP'

      def help_hint = "Use 'wifiwand help' or 'wifiwand -h' for help."

      def print_help
        @printed_help = true
      end

      def resolve_command(command_name)
        @last_lookup = command_name
        nil
      end
    end.new
  end

  it_behaves_like 'binds command context', bound_attributes: { output: -> { cli.out_stream } }

  describe '#help_text' do
    it 'returns global help text when bound' do
      command = described_class.new.bind(cli)

      expect(command.help_text).to eq('GLOBAL HELP')
    end

    it 'returns usage when unbound' do
      expect(described_class.new.help_text).to eq('Usage: wifiwand help [command]')
    end
  end

  describe '#call' do
    subject(:command) do
      described_class.new(
        metadata: described_class.new.metadata,
        cli:      cli,
        output:   output
      )
    end

    it 'prints command-specific help when available' do
      help_target = double('command', help_text: 'COMMAND HELP')
      allow(cli).to receive(:resolve_command).with('log').and_return(help_target)

      command.call('log')

      expect(output.string).to eq("COMMAND HELP\n")
      expect(cli.printed_help).to be(false)
    end

    it 'falls back to global help when no command is provided' do
      allow(cli).to receive(:resolve_command).with(nil).and_return(nil)

      command.call

      expect(cli.printed_help).to be(true)
    end

    it 'falls back to global help when command-specific help is unavailable' do
      help_target = double('command', help_text: nil)
      allow(cli).to receive(:resolve_command).with('unknown').and_return(help_target)

      command.call('unknown')

      expect(cli.printed_help).to be(true)
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(cli).not_to receive(:resolve_command)
      expect(cli).not_to receive(:print_help)

      expect { command.call('log', 'extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand help [command]')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end
  end
end
