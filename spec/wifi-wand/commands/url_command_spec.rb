# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/url_command'

describe WifiWand::UrlCommand do
  let(:cli) { double('cli') }

  it_behaves_like 'binds command context', bound_attributes: {}

  it_behaves_like 'has default command help text',
    usage:       'Usage: wifi-wand url',
    description: 'project repository URL'

  describe '#call' do
    it 'returns the project URL' do
      expect(described_class.new.call).to eq('https://github.com/keithrbennett/wifiwand')
    end
  end
end
