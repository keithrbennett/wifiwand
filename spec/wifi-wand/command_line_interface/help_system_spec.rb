# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/command_line_interface/help_system'
require_relative '../../../lib/wifi-wand/version'
require_relative '../../../lib/wifi-wand/timing_constants'

describe WifiWand::CommandLineInterface::HelpSystem do
  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::HelpSystem

      attr_accessor :model

      def initialize(model = nil)
        @model = model
      end
    end
  end

  let(:resource_manager) { double("ResourceManager") }
  let(:model) { double("Model", resource_manager: resource_manager) }
  subject { test_class.new(model) }

  before do
    allow(resource_manager).to receive(:open_resources).and_return(double("OpenResources", help_string: "test resource help"))
  end

  describe '#help_text' do
    let(:help) { subject.help_text }

    it 'returns a string' do
      expect(help).to be_a(String)
    end

    it 'includes the gem version' do
      expect(help).to include(WifiWand::VERSION)
    end

    it 'includes the default wait interval' do
      expect(help).to include(WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL.to_s)
    end

    it 'includes the resource help string' do
      expect(help).to include("test resource help")
    end

    context "when model is not available" do
      subject { test_class.new(nil) }

      it "shows resources as unavailable" do
        expect(help).to include("[resources unavailable]")
      end
    end
  end

  describe '#print_help' do
    it 'prints the help text to stdout' do
      expect { subject.print_help }.to output(subject.help_text).to_stdout
    end
  end

  describe '#help_hint' do
    it 'returns the correct help hint string' do
      expect(subject.help_hint).to eq("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
    end
  end
end
