# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/command_line_interface'

describe WifiWand::Commands::Base do
  describe WifiWand::Commands::Base::LazyModel do
    subject(:lazy_model) { described_class.new(cli) }

    let(:model_class) do
      Class.new do
        attr_reader :ssid

        def initialize(ssid) = @ssid = ssid

        def ==(other) = other.is_a?(self.class) && other.ssid == ssid
        alias_method :eql?, :==

        def hash = ssid.hash
        def inspect = "#<Model #{ssid}>"
        def greet(name, punctuation: '!') = "hello #{name}#{punctuation}"

        private def secret = 'hidden'
      end
    end
    let(:model) { model_class.new('HomeNet') }
    let(:cli) { double('cli', model: model) }

    it 'does not build the model until it is used' do
      lazy_cli = double('cli')
      allow(lazy_cli).to receive(:model).and_return(model)

      described_class.new(lazy_cli)

      expect(lazy_cli).not_to have_received(:model)
    end

    it 'forwards public calls with their arguments to the model' do
      expect(lazy_model.greet('Ann', punctuation: '?')).to eq('hello Ann?')
    end

    it 'does not forward calls to private model methods' do
      expect { lazy_model.secret }.to raise_error(NoMethodError)
    end

    describe '#respond_to?' do
      it 'is true for public model methods' do
        expect(lazy_model).to respond_to(:greet)
      end

      it 'is false for private model methods by default' do
        expect(lazy_model).not_to respond_to(:secret)
      end

      it 'is true for private model methods when private methods are requested' do
        expect(lazy_model.respond_to?(:secret, true)).to be(true)
      end

      it 'is false for methods the model does not have' do
        expect(lazy_model).not_to respond_to(:no_such_method)
      end
    end

    it 'compares equal to an equal model' do
      expect(lazy_model == model_class.new('HomeNet')).to be(true)
      expect(lazy_model == model_class.new('Other')).to be(false)
    end

    it 'is eql? to an equal model' do
      expect(lazy_model.eql?(model_class.new('HomeNet'))).to be(true)
      expect(lazy_model.eql?(model_class.new('Other'))).to be(false)
    end

    it 'hashes like the model' do
      expect(lazy_model.hash).to eq(model.hash)
    end

    it 'inspects like the model' do
      expect(lazy_model.inspect).to eq('#<Model HomeNet>')
    end
  end

  describe 'command metadata' do
    let(:metadata_class) { WifiWand::Commands::Metadata }

    describe '.declared_metadata' do
      it 'is nil for a command that declares nothing and has no declaring ancestor' do
        expect(Class.new(described_class).declared_metadata).to be_nil
      end

      it 'is inherited from the nearest declaring ancestor' do
        parent = Class.new(described_class) do
          command_metadata(short_string: 'p', long_string: 'parent', description: 'A parent')
        end
        child = Class.new(parent)

        expect(child.declared_metadata).to be(parent.declared_metadata)
        expect(child.declared_metadata.long_string).to eq('parent')
      end

      it 'is overridden by a declaration on the subclass itself' do
        parent = Class.new(described_class) do
          command_metadata(short_string: 'p', long_string: 'parent')
        end
        child = Class.new(parent) do
          command_metadata(short_string: 'c', long_string: 'child')
        end

        expect(child.declared_metadata.long_string).to eq('child')
        expect(parent.declared_metadata.long_string).to eq('parent')
      end
    end

    describe 'constant-based declarations' do
      let(:legacy_class) do
        Class.new(described_class) do
          const_set(:SHORT_NAME, 'lg')
          const_set(:LONG_NAME, 'legacy')
          const_set(:DESCRIPTION, 'An older style command')
          const_set(:USAGE, 'legacy [args]')
        end
      end

      it 'builds metadata from the class constants when none is declared' do
        metadata = legacy_class.new.metadata

        expect(metadata).to have_attributes(
          short_string: 'lg', long_string: 'legacy', description: 'An older style command',
          usage: 'legacy [args]'
        )
        expect(legacy_class.new.aliases).to eq(%w[lg legacy])
      end

      it 'prefers an explicit metadata argument over the constants' do
        explicit = metadata_class.new(short_string: 'x', long_string: 'explicit')

        expect(legacy_class.new(metadata: explicit).metadata).to be(explicit)
      end
    end
  end
end
