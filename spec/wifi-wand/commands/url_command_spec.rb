# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/url_command'

describe WifiWand::UrlCommand do
  let(:output_support) { double('output_support') }
  let(:cli) { double('cli', output_support: output_support) }

  it_behaves_like 'binds command context',
    bound_attributes: { output_support: :output_support }

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand url',
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
  end
end
