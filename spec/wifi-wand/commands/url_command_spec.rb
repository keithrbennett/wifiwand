# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/commands/url_command'

describe WifiWand::UrlCommand do
  describe '#bind' do
    it 'returns the same command instance' do
      command = described_class.new

      expect(command.bind(double('cli'))).to equal(command)
    end
  end

  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include('Usage: wifi-wand url')
      expect(help).to include('project repository URL')
    end
  end

  describe '#call' do
    it 'returns the project URL' do
      expect(described_class.new.call).to eq('https://github.com/keithrbennett/wifiwand')
    end
  end
end
