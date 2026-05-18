# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/wifi_wand/commands/help_system'
require_relative '../../../lib/wifi_wand/version'
require_relative '../../../lib/wifi_wand/timing_constants'

describe WifiWand::Commands::HelpSystem do
  subject { test_class.new(model) }

  let(:test_class) do
    Class.new do
      include WifiWand::Commands::HelpSystem

      attr_accessor :model

      def initialize(model = nil) = @model = model
    end
  end

  let(:resource_manager) { double('ResourceManager') }
  let(:model) { double('Model') }

  before do
    open_resources = double('OpenResources', help_string: 'test resource help')
    allow(WifiWand::Helpers::ResourceManager).to receive(:new).and_return(resource_manager)
    allow(resource_manager).to receive(:open_resources).and_return(open_resources)
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
      expect(help).to include('test resource help')
    end

    it 'includes the repository URL' do
      expect(help).to include(WifiWand::Commands::HelpSystem::REPOSITORY_URL)
    end

    it 'includes the local documentation path' do
      expect(help).to include(
        "Documentation (Local): #{WifiWand::Commands::HelpSystem::LOCAL_README_PATH}"
      )
    end

    it 'includes horizontal rule separators' do
      expect(help).to include(WifiWand::Commands::HelpSystem::HORIZONTAL_RULE)
    end

    it 'includes Usage line' do
      expect(help).to include('Usage:                 wifi-wand [options] command [args]')
    end

    it 'documents DNS in the status command description' do
      expect(help).to include('status line (WiFi, Network, DNS, Internet')
    end

    it 'documents the global utc timestamp option' do
      expect(help).to include('-u, --utc BOOLEAN')
      expect(help).to include('use UTC for timestamps (default: false, for local time)')
    end

    it 'documents exact short and long command forms for public_ip' do
      expect(help).to include('pi / public_ip [address|country|both|a|c|b]')
      expect(help).to include("e.g. 'public_ip a' or 'pi country'")
    end

    it 'lists shell with the normal commands' do
      expect(help).to include('sh / shell')
      expect(help).not_to include('Subcommands')
    end

    it 'uses the log command-owned help summary' do
      allow(WifiWand::Commands::Log).to receive(:help_summary_lines).and_call_original

      help

      expect(WifiWand::Commands::Log).to have_received(:help_summary_lines)
      expect(help).to include('options: --interval N (default 5 seconds),')
      expect(help).to include('--stdout (keep stdout when file destination is used)')
    end

    it 'wraps long switch labels onto their own line before the description' do
      expect(help).to match(/^\s{2}-p, --wifi-interface interface_name\n\s{38}specify WiFi interface name/m)
    end

    it 'wraps long command labels onto their own line before the description' do
      pattern = Regexp.new(
        '^\s{2}pi / public_ip \[address\|country\|both\|a\|c\|b\]\n' \
          '\s{38}public IP lookup; selectors may use long or',
        Regexp::MULTILINE
      )

      expect(help).to match(pattern)
    end

    context 'when model is not available' do
      subject { test_class.new(nil) }

      it 'still includes the resource help string' do
        expect(help).to include('test resource help')
      end
    end
  end

  describe '#print_help' do
    it 'prints the help text to stdout' do
      expect { subject.print_help }.to output(subject.help_text).to_stdout
    end

    it 'uses $stdout explicitly when interactive_mode is true' do
      subject.define_singleton_method(:interactive_mode) { true }
      out_io = StringIO.new
      subject.instance_variable_set(:@out_stream, out_io)

      expect { subject.print_help }.to output(subject.help_text).to_stdout
      expect(out_io.string).to eq('')
    end
  end

  describe '#help_hint' do
    it 'returns the correct help hint string' do
      expect(subject.help_hint).to eq("Use 'wifi-wand help' or 'wifi-wand -h' for help.")
    end
  end
end
