# frozen_string_literal: true

require_relative('../spec_helper')
require_relative('../../lib/wifi-wand/command_line_parser')

describe WifiWand::CommandLineParser do
  let(:err_stream) { StringIO.new }

  def parse_with_argv(*args)
    described_class.new(args, ENV, err_stream).parse
  end

  describe '#parse' do
    it 'parses verbose flags' do
      options = parse_with_argv('--verbose', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('-v', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('--no-verbose', 'info')
      expect(options.verbose).to be(false)
    end

    it 'defaults verbose to nil when not specified' do
      options = parse_with_argv('info')
      expect(options.verbose).to be_nil
    end

    %w[--no-v --no-verbose].each do |negation_flag|
      it "handles verbose flag negation when -v is followed by #{negation_flag}" do
        options = parse_with_argv('-v', negation_flag, 'info')
        expect(options.verbose).to be(false)
      end
    end

    it 'parses shell subcommand and sets interactive_mode' do
      options = parse_with_argv('shell')
      expect(options.interactive_mode).to be(true)
      expect(options.argv).to eq([])
    end

    it 'parses wifi interface options' do
      options = parse_with_argv('--wifi-interface', 'wlan0', 'info')
      expect(options.wifi_interface).to eq('wlan0')

      options = parse_with_argv('-p', 'en0', 'info')
      expect(options.wifi_interface).to eq('en0')
    end

    it 'parses output format options' do
      options = parse_with_argv('--output_format', 'j', 'info')
      expect(options.post_processor).to respond_to(:call)

      options = parse_with_argv('-o', 'y', 'info')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'handles invalid output format' do
      expect do
        described_class.new(['-o', 'z', 'info'], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError)
    end

    it 'handles unrecognized flags' do
      expect do
        described_class.new(['--invalid-flag'], ENV, err_stream).parse
      end.to raise_error(OptionParser::InvalidOption)
    end

    it 'normalizes --help into the help command' do
      options = described_class.new(['--help'], ENV, err_stream).parse
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['h'])
    end

    it 'normalizes leading help flags combined with a command into the help command' do
      options = described_class.new(['-h', 'info'], ENV, err_stream).parse
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['h'])
    end

    it 'raises for trailing help flags after a command' do
      expect do
        described_class.new(['info', '-h'], ENV, err_stream).parse
      end.to raise_error(OptionParser::InvalidOption, /must appear before the command/)
    end

    it 'raises for other trailing global options after a command' do
      expect do
        described_class.new(['info', '--version'], ENV, err_stream).parse
      end.to raise_error(OptionParser::InvalidOption, /must appear before the command/)

      expect do
        described_class.new(['info', '--wifi-interface', 'en0'], ENV, err_stream).parse
      end.to raise_error(OptionParser::InvalidOption, /must appear before the command/)
    end

    it 'leaves command-specific options after a command untouched' do
      options = described_class.new(['log', '--file', 'wifi.log'], ENV, err_stream).parse
      expect(options.argv).to eq(['log', '--file', 'wifi.log'])
    end

    it 'parses version flags' do
      options = parse_with_argv('--version')
      expect(options.version_requested).to be(true)

      options = parse_with_argv('-V')
      expect(options.version_requested).to be(true)
    end

    it 'returns command argv without the parsed options' do
      options = described_class.new(['-v', '-p', 'wlan0', 'connect', 'TestNetwork'], ENV, err_stream).parse
      expect(options.argv).to eq(%w[connect TestNetwork])
    end

    it 'handles multiple flags together' do
      options = described_class.new(['-v', '-p', 'eth0', '--output_format', 'j', 'info'], ENV,
        err_stream).parse
      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'handles shell subcommand alongside other flags' do
      options = described_class.new(['-v', '-p', 'eth0', 'shell'], ENV, err_stream).parse
      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.interactive_mode).to be(true)
      expect(options.argv).to eq([])
    end

    it 'prepends options from WIFIWAND_OPTS before CLI arguments' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose')

      options = described_class.new(['info'], ENV, err_stream).parse

      expect(options.verbose).to be(true)
      expect(options.argv).to eq(['info'])
    end

    it 'allows explicit command-line flags to override WIFIWAND_OPTS defaults' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose --wifi-interface en0')

      options = described_class.new(['--no-verbose', '--wifi-interface', 'en1', 'info'], ENV,
        err_stream).parse

      expect(options.verbose).to be(false)
      expect(options.wifi_interface).to eq('en1')
    end

    it 'raises a configuration error when WIFIWAND_OPTS cannot be parsed' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose "')

      expect do
        described_class.new(['info'], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /WIFIWAND_OPTS/)
    end

    it 'does not mutate the argv array passed to it' do
      input = ['-v', '-p', 'wlan0', 'connect', 'TestNetwork']
      original = input.dup
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(original)
    end

    it 'does not mutate the argv array when parsing shell subcommand' do
      input = ['-v', 'shell']
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(['-v', 'shell'])
    end

    it 'does not mutate the argv array when help is requested' do
      input = ['-h', 'info']
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(['-h', 'info'])
    end
  end

  describe 'output format processors' do
    it 'creates JSON processor' do
      options = parse_with_argv('-o', 'j', 'info')
      result = options.post_processor.call({ 'test' => 'value' })
      expect(JSON.parse(result)).to eq({ 'test' => 'value' })
    end

    it 'creates YAML processor' do
      options = parse_with_argv('-o', 'y', 'info')
      result = options.post_processor.call({ 'test' => 'value' })
      expect(YAML.load(result)).to eq({ 'test' => 'value' })
    end

    it 'creates inspect processor' do
      options = parse_with_argv('-o', 'i', 'info')
      result = options.post_processor.call({ 'test' => 'value' })
      expect(result).to eq({ 'test' => 'value' }.inspect)
    end

    it 'creates pretty JSON processor' do
      options = parse_with_argv('-o', 'k', 'info')
      result = options.post_processor.call({ 'test' => 'value' })
      expect(JSON.parse(result)).to eq({ 'test' => 'value' })
      expect(result).to include("\n")
    end

    it 'creates StringIO processor' do
      options = parse_with_argv('-o', 'p', 'info')
      test_data = { 'test' => 'value' }
      result = options.post_processor.call(test_data)
      expect(result).to eq("#{test_data}\n")
    end
  end
end
