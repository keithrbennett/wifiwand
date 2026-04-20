# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi-wand/main')

describe WifiWand::Main do
  subject { described_class.new(out_stream, err_stream, argv: ARGV) }

  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }


  def parse_with_argv(*args)
    stub_const('ARGV', args)
    described_class.new(out_stream, err_stream, argv: ARGV).parse_command_line
  end

  describe '#parse_command_line' do
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

    it 'parses shell subcommand into explicit argv without mutating ARGV' do
      options = parse_with_argv('shell')
      expect(options.interactive_mode).to be(true)
      expect(options.argv).to eq([])
      expect(ARGV).to eq(['shell'])
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
      stub_const('ARGV', ['-o', 'z', 'info'])  # 'z' is not a valid format
      expect { subject.parse_command_line }.to raise_error(WifiWand::ConfigurationError)
    end

    it 'handles unrecognized flags' do
      stub_const('ARGV', ['--invalid-flag'])
      expect { subject.parse_command_line }.to raise_error(OptionParser::InvalidOption)
    end

    it 'parses help-only argv into the help command without mutating ARGV' do
      stub_const('ARGV', ['--help'])
      options = subject.parse_command_line
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['h'])
      expect(ARGV).to eq(['--help'])
    end

    it 'normalizes leading help flags combined with a command into the help command' do
      stub_const('ARGV', ['-h', 'info'])
      options = subject.parse_command_line
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['h'])
      expect(ARGV).to eq(['-h', 'info'])
    end

    it 'normalizes trailing help flags combined with a command into the help command' do
      stub_const('ARGV', ['info', '-h'])
      options = subject.parse_command_line
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['h'])
      expect(ARGV).to eq(['info', '-h'])
    end

    it 'parses version flags' do
      options = parse_with_argv('--version')
      expect(options.version_requested).to be(true)

      options = parse_with_argv('-V')
      expect(options.version_requested).to be(true)
    end

    it 'returns command argv without mutating ARGV' do
      stub_const('ARGV', ['-v', '-p', 'wlan0', 'connect', 'TestNetwork'])
      options = subject.parse_command_line

      expect(options.argv).to eq(%w[connect TestNetwork])
      expect(ARGV).to eq(['-v', '-p', 'wlan0', 'connect', 'TestNetwork'])
    end

    it 'handles multiple flags together' do
      stub_const('ARGV', ['-v', '-p', 'eth0', '--output_format', 'j', 'info'])
      options = subject.parse_command_line

      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'handles shell subcommand alongside other flags' do
      stub_const('ARGV', ['-v', '-p', 'eth0', 'shell'])
      options = subject.parse_command_line

      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.interactive_mode).to be(true)
      expect(options.argv).to eq([])
      expect(ARGV).to eq(['-v', '-p', 'eth0', 'shell'])
    end

    it 'prepends options from WIFIWAND_OPTS before CLI arguments' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose')
      stub_const('ARGV', ['info'])

      options = subject.parse_command_line

      expect(options.verbose).to be(true)
      expect(options.argv).to eq(['info'])
      expect(ARGV).to eq(['info'])
    end

    it 'allows explicit command-line flags to override WIFIWAND_OPTS defaults' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose --wifi-interface en0')
      stub_const('ARGV', ['--no-verbose', '--wifi-interface', 'en1', 'info'])

      options = subject.parse_command_line

      expect(options.verbose).to be(false)
      expect(options.wifi_interface).to eq('en1')
    end

    it 'raises a configuration error when WIFIWAND_OPTS cannot be parsed' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose "')
      stub_const('ARGV', ['info'])

      expect { subject.parse_command_line }.to raise_error(WifiWand::ConfigurationError, /WIFIWAND_OPTS/)
    end
  end

  describe '#call' do
    let(:mock_cli) { double('CommandLineInterface') }

    before do
      # Mock the command line parsing to avoid complex setup
      options = OpenStruct.new(verbose: false, interactive_mode: false, argv: ['info'])
      allow(subject).to receive(:parse_command_line).and_return(options)
      # Mock CLI creation to avoid OS detection
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'creates CLI with parsed options and calls it' do
      options = OpenStruct.new(verbose: true, wifi_interface: 'wlan0', argv: ['info'])
      allow(subject).to receive(:parse_command_line).and_return(options)

      expect(WifiWand::CommandLineInterface)
        .to receive(:new).with(options, argv: ['info']).and_return(mock_cli)
      expect(mock_cli).to receive(:call).and_return(0)

      expect(subject.call).to eq(0)
    end

    it 'handles and prints exceptions and returns code 1' do
      allow(mock_cli).to receive(:call).and_raise(StandardError.new('Test error'))
      expect(subject.call).to eq(1)
      expect(err_stream.string).to match(/Error:.*Test error/m)
    end

    it 'prints clean error messages without backtraces by default and returns code 1' do
      ex = StandardError.new('Test error')
      allow(ex).to receive(:backtrace).and_return(%w[line1 line2 line3])
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to eq("Error: Test error\n")
    end

    it 'prints backtrace only in verbose mode and returns code 1' do
      ex = StandardError.new('Test error')
      allow(ex).to receive(:backtrace).and_return(%w[line1 line2 line3])
      allow(mock_cli).to receive(:call).and_raise(ex)

      # Mock verbose mode
      options = OpenStruct.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(subject).to receive(:parse_command_line).and_return(options)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to match(/Error: Test error/)
      expect(err_stream.string).to match(/Stack trace:/)
    end

    it 'returns code 1 for interactive-mode failures too' do
      ex = StandardError.new('Shell startup failed')
      options = OpenStruct.new(verbose: false, interactive_mode: true, argv: [])
      allow(subject).to receive(:parse_command_line).and_return(options)
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to match(/Error: Shell startup failed/)
    end

    it 'succeeds when no exceptions occur' do
      expect(mock_cli).to receive(:call).and_return(0)
      expect(subject.call).to eq(0)
      expect(out_stream.string).to be_empty
    end

    it 'prints version and skips CLI initialization when requested' do
      stub_const('ARGV', ['-V'])
      main = described_class.new(out_stream, err_stream, argv: ARGV)

      expect(WifiWand::CommandLineInterface).not_to receive(:new)

      expect(main.call).to eq(0)

      expect(out_stream.string).to eq("#{WifiWand::VERSION}\n")
    end

    it 'returns immediately after printing version even when other arguments are present' do
      stub_const('ARGV', ['--version', 'info'])
      main = described_class.new(out_stream, err_stream, argv: ARGV)

      expect(WifiWand::CommandLineInterface).not_to receive(:new)

      expect(main.call).to eq(0)

      expect(out_stream.string).to eq("#{WifiWand::VERSION}\n")
    end
  end

  describe 'output format processors' do
    it 'creates JSON processor' do
      stub_const('ARGV', ['-o', 'j', 'info'])  # 'j' for json
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = { 'test' => 'value' }
      result = processor.call(test_data)

      expect(result).to be_a(String)
      expect(JSON.parse(result)).to eq(test_data)
    end

    it 'creates YAML processor' do
      stub_const('ARGV', ['-o', 'y', 'info'])  # 'y' for yaml
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = { 'test' => 'value' }
      result = processor.call(test_data)

      expect(result).to be_a(String)
      expect(YAML.load(result)).to eq(test_data)
    end

    it 'creates inspect processor' do
      stub_const('ARGV', ['-o', 'i', 'info'])  # 'i' for inspect
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = { 'test' => 'value' }
      result = processor.call(test_data)

      expect(result).to eq(test_data.inspect)
    end

    it 'creates pretty JSON processor' do
      stub_const('ARGV', ['-o', 'k', 'info'])  # 'k' for pretty JSON
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = { 'test' => 'value' }
      result = processor.call(test_data)

      expect(result).to be_a(String)
      parsed_result = JSON.parse(result)
      expect(parsed_result).to eq(test_data)
      expect(result).to include("\n")  # Pretty formatting includes newlines
    end

    it 'creates StringIO processor' do
      stub_const('ARGV', ['-o', 'p', 'info'])  # 'p' for puts via StringIO
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = { 'test' => 'value' }
      result = processor.call(test_data)

      expect(result).to be_a(String)
      expect(result).to eq("#{test_data}\n")
    end
  end

  describe 'integration workflow' do
    let(:mock_cli) { double('CommandLineInterface') }

    before do
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'parses arguments and executes CLI with correct options' do
      stub_const('ARGV', ['-v', '-p', 'wlan0', 'shell'])

      expect(WifiWand::CommandLineInterface).to receive(:new) do |options, argv:|
        expect(options.verbose).to be(true)
        expect(options.interactive_mode).to be(true)
        expect(options.wifi_interface).to eq('wlan0')
        expect(argv).to eq([])
        mock_cli
      end
      expect(mock_cli).to receive(:call).and_return(0)

      expect(subject.call).to eq(0)
    end

    it 'handles complete workflow with output formatting' do
      stub_const('ARGV', ['-o', 'j', 'info'])

      expect(WifiWand::CommandLineInterface).to receive(:new) do |options, argv:|
        expect(options.post_processor).to respond_to(:call)
        expect(argv).to eq(['info'])
        mock_cli
      end
      expect(mock_cli).to receive(:call).and_return(0)

      expect(subject.call).to eq(0)
    end
  end

  describe '#handle_error' do
    let(:mock_cli) { double('CommandLineInterface') }

    before do
      options = OpenStruct.new(verbose: false, interactive_mode: false, argv: ['info'])
      allow(subject).to receive(:parse_command_line).and_return(options)
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'handles OsCommandError with specific error message and returns code 1' do
      ex = os_command_error(exitstatus: 1, command: 'a command', text: 'a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expected_output = <<~MESSAGE

        Error: a message
        Command failed: a command
        Exit code: 1
      MESSAGE

      expect(subject.call).to eq(1)
      expect(err_stream.string).to eq(expected_output)
    end

    it 'handles WifiWand::Error with a simple error message and returns code 1' do
      ex = WifiWand::Error.new('a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to eq("Error: a message\n")
    end

    it 'handles other errors with a simple error message and returns code 1' do
      ex = StandardError.new('a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to eq("Error: a message\n")
    end

    it 'handles other errors with a stack trace in verbose mode and returns code 1' do
      ex = StandardError.new('a message')
      allow(ex).to receive(:backtrace).and_return(['line 1', 'line 2'])
      allow(mock_cli).to receive(:call).and_raise(ex)
      # Mock verbose mode
      options = OpenStruct.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(subject).to receive(:parse_command_line).and_return(options)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to match(/Error: a message/)
      expect(err_stream.string).to match(/Stack trace:/)
    end
  end

  describe 'help flag behavior' do
    [
      ['--help'],
      ['-h'],
      ['-h', 'info'],
      ['info', '-h'],
    ].each do |argv|
      it "prints help for #{argv.join(' ')} without initializing the model" do
        expect(WifiWand).not_to receive(:create_model)

        out_stream = StringIO.new
        err_stream = StringIO.new
        main = described_class.new(out_stream, err_stream, argv: argv)

        expect(main.call).to eq(0)
        expect(out_stream.string).to include('Command Line Switches')
        expect(err_stream.string).to eq('')
      end
    end
  end
end
