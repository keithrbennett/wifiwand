# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi_wand/repl_context'
require_relative '../../lib/wifi_wand/commands/registry'

RSpec.describe WifiWand::ReplContext do
  let(:registry_aliases) do
    Object.new.extend(WifiWand::Commands::Registry).commands.flat_map(&:aliases).to_set
  end

  let(:repl_methods) do
    described_class.public_instance_methods(false).map(&:to_s).to_set
  end

  it 'has a method for every registered command alias' do
    registry_aliases.each do |alias_name|
      expect(repl_methods).to include(alias_name),
        "ReplContext is missing a method for command alias '#{alias_name}'"
    end
  end

  it 'has no methods that are not registered command aliases' do
    allowed = registry_aliases | described_class::REPL_ONLY_METHODS.to_set
    expect(repl_methods - allowed).to be_empty
  end
end
