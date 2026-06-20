# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/url'

describe WifiWand::Commands::Url do
  let(:output_support) { double('output_support') }
  let(:cli) do
    double('cli', output_support: output_support,
      help_hint: "Use 'wifiwand help' or 'wifiwand -h' for help.")
  end

  it_behaves_like 'binds command context',
    bound_attributes: { output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifiwand url',
    description: 'project repository URL'

  describe '#call' do
    subject(:command) { described_class.new.bind(cli) }

    it 'routes the project URL through handle_output' do
      expect(output_support).to receive(:handle_output) do |url, producer|
        expect(url).to eq('https://github.com/keithrbennett/wifiwand')
        expect(producer.call).to eq('https://github.com/keithrbennett/wifiwand')
      end

      command.call
    end

    it 'raises a usage-oriented error when extra arguments are provided' do
      expect(output_support).not_to receive(:handle_output)

      expect { command.call('extra') }
        .to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include('Unexpected argument(s): extra')
          expect(error.message).to include('Usage: wifiwand url')
          expect(error.message).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        }
    end
  end
end
