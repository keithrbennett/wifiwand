# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/quit_command'

describe WifiWand::QuitCommand do
  let(:cli) { double('cli', help_hint: "Use 'wifi-wand help' or 'wifi-wand -h' for help.") }

  it_behaves_like 'binds command context', bound_attributes: {}

  describe '#aliases' do
    it 'includes quit and xit aliases' do
      expect(described_class.new.aliases).to eq(%w[q quit x xit])
    end
  end

  describe '#help_text' do
    it 'includes usage, description, and xit aliases' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand quit')
      expect(help).to include('exit this program in interactive shell mode')
      expect(help).to include('Also available as: x, xit')
    end
  end

  describe '#call' do
    it 'delegates to cli.quit' do
      command = described_class.new.bind(cli)
      expect(cli).to receive(:quit)

      command.call
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      command = described_class.new.bind(cli)
      expect(cli).not_to receive(:quit)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifi-wand quit')
          expect(error.message).to include("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
        }
    end
  end
end
