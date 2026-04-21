# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi-wand/main')

describe WifiWand::Main do
  subject { described_class.new(out_stream, err_stream, argv: ARGV) }

  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }
  let(:default_options) { OpenStruct.new(verbose: false, interactive_mode: false, argv: ['info']) }
  let(:mock_parser) { instance_double(WifiWand::CommandLineParser, parse: default_options) }

  describe '#call' do
    let(:mock_cli) { double('CommandLineInterface') }

    before do
      allow(WifiWand::CommandLineParser).to receive(:new).and_return(mock_parser)
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'creates CLI with parsed options and calls it' do
      options = OpenStruct.new(verbose: true, wifi_interface: 'wlan0', argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

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

      options = OpenStruct.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to match(/Error: Test error/)
      expect(err_stream.string).to match(/Stack trace:/)
    end

    it 'returns code 1 for interactive-mode failures too' do
      ex = StandardError.new('Shell startup failed')
      options = OpenStruct.new(verbose: false, interactive_mode: true, argv: [])
      allow(mock_parser).to receive(:parse).and_return(options)
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
      allow(mock_parser).to receive(:parse).and_return(OpenStruct.new(version_requested: true))

      expect(WifiWand::CommandLineInterface).not_to receive(:new)
      expect(subject.call).to eq(0)
      expect(out_stream.string).to eq("#{WifiWand::VERSION}\n")
    end

    it 'returns immediately after printing version even when other options are present' do
      allow(mock_parser).to receive(:parse).and_return(
        OpenStruct.new(version_requested: true, verbose: true)
      )

      expect(WifiWand::CommandLineInterface).not_to receive(:new)
      expect(subject.call).to eq(0)
      expect(out_stream.string).to eq("#{WifiWand::VERSION}\n")
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
      allow(WifiWand::CommandLineParser).to receive(:new).and_return(mock_parser)
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

      options = OpenStruct.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

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

    it 'passes trailing -h through to the command instead of treating it as top-level help' do
      mock_cli = double('CommandLineInterface')
      expect(mock_cli).to receive(:call).and_return(0)

      out_stream = StringIO.new
      err_stream = StringIO.new
      main = described_class.new(out_stream, err_stream, argv: ['info', '-h'])

      expect(WifiWand::CommandLineInterface).to receive(:new) do |options, argv:|
        expect(options.help_requested).to be_nil
        expect(argv).to eq(['info', '-h'])
        mock_cli
      end

      expect(main.call).to eq(0)
      expect(out_stream.string).to eq('')
      expect(err_stream.string).to eq('')
    end
  end
end
