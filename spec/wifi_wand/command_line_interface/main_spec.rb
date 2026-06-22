# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi_wand/main')

describe WifiWand::Main do
  subject { described_class.new(out_stream, err_stream, argv: ARGV) }

  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }
  let(:default_options) { WifiWand::CommandLineOptions.new(verbose: false, interactive_mode: false, argv: ['info']) }
  let(:mock_parser) { instance_double(WifiWand::CommandLineParser, parse: default_options) }

  describe '#call' do
    let(:mock_cli) { double('CommandLineInterface') }

    before do
      allow(WifiWand::CommandLineParser).to receive(:new).and_return(mock_parser)
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'creates CLI with parsed options and calls it' do
      options = WifiWand::CommandLineOptions.new(verbose: true, wifi_interface: 'wlan0', argv: ['info'])
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

    it 'handles interrupts by printing a friendly message and returning code 130' do
      allow(mock_cli).to receive(:call).and_raise(Interrupt)

      expect(subject.call).to eq(130)
      expect(err_stream.string).to eq("\nError: Interrupted by Ctrl-C while running command: info.\n")
    end

    it 'prints backtrace of the interrupt in verbose mode' do
      error = Interrupt.new
      allow(error).to receive(:backtrace).and_return(['/lib/wifi_wand/model.rb:10', 'other_file.rb:5'])
      allow(mock_cli).to receive(:call).and_raise(error)

      options = WifiWand::CommandLineOptions.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

      expect(subject.call).to eq(130)
      expect(err_stream.string).to include('Error: Interrupted by Ctrl-C while running command: info.')
      expect(err_stream.string).to include('Interrupted at: /lib/wifi_wand/model.rb:10')
    end

    it 'handles interrupts that occur during option parsing before options are populated' do
      allow(mock_parser).to receive(:parse).and_raise(Interrupt)

      expect(subject.call).to eq(130)
      expect(err_stream.string).to eq("\nError: Interrupted by Ctrl-C.\n")
    end

    it 'prints backtrace only in verbose mode and returns code 1' do
      ex = StandardError.new('Test error')
      allow(ex).to receive(:backtrace).and_return(%w[line1 line2 line3])
      allow(mock_cli).to receive(:call).and_raise(ex)

      options = WifiWand::CommandLineOptions.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to include('Error: Test error')
      expect(err_stream.string).to include('Stack trace:')
    end

    it 'returns code 1 for shell command failures too' do
      ex = StandardError.new('Shell startup failed')
      options = WifiWand::CommandLineOptions.new(verbose: false, argv: ['shell'])
      allow(mock_parser).to receive(:parse).and_return(options)
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to include('Error: Shell startup failed')
    end

    it 'succeeds when no exceptions occur' do
      expect(mock_cli).to receive(:call).and_return(0)
      expect(subject.call).to eq(0)
      expect(out_stream.string).to be_empty
    end

    it 'prints version and skips CLI initialization when requested' do
      allow(mock_parser).to receive(:parse).and_return(
        WifiWand::CommandLineOptions.new(version_requested: true)
      )

      expect(WifiWand::CommandLineInterface).not_to receive(:new)
      expect(subject.call).to eq(0)
      expect(out_stream.string).to eq("#{WifiWand::VERSION}\n")
    end

    it 'returns immediately after printing version even when other options are present' do
      allow(mock_parser).to receive(:parse).and_return(
        WifiWand::CommandLineOptions.new(version_requested: true, verbose: true)
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
      stub_const('ARGV', ['-v', 'true', '-p', 'wlan0', 'info'])

      expect(WifiWand::CommandLineInterface).to receive(:new) do |options, argv:|
        expect(options.verbose).to be(true)
        expect(options.interactive_mode).to be_nil
        expect(options.wifi_interface).to eq('wlan0')
        expect(argv).to eq(['info'])
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

    it 'handles silent OsCommandError without printing a blank error line' do
      ex = os_command_error(exitstatus: 7, command: 'silent command', text: '')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expected_output = <<~MESSAGE

        Error: Command failed: silent command
        Exit code: 7
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

      options = WifiWand::CommandLineOptions.new(verbose: true, interactive_mode: false, argv: ['info'])
      allow(mock_parser).to receive(:parse).and_return(options)

      expect(subject.call).to eq(1)
      expect(err_stream.string).to include('Error: a message')
      expect(err_stream.string).to include('Stack trace:')
    end
  end

  describe 'help flag behavior' do
    [
      ['--help'],
      ['-h'],
    ].each do |argv|
      it "prints global help for #{argv.join(' ')} without initializing the model" do
        expect(WifiWand).not_to receive(:create_model)

        out_stream = StringIO.new
        err_stream = StringIO.new
        main = described_class.new(out_stream, err_stream, argv: argv)

        expect(main.call).to eq(0)
        expect(out_stream.string).to include('Command Line Switches')
        expect(err_stream.string).to eq('')
      end
    end

    it 'prints command help for -h info without initializing the model' do
      expect(WifiWand).not_to receive(:create_model)

      out_stream = StringIO.new
      err_stream = StringIO.new
      main = described_class.new(out_stream, err_stream, argv: ['-h', 'info'])

      expect(main.call).to eq(0)
      expect(out_stream.string).to include('Usage: wifiwand info')
      expect(err_stream.string).to eq('')
    end

    it 'normalizes trailing -h into command help' do
      mock_cli = double('CommandLineInterface')
      expect(mock_cli).to receive(:call).and_return(0)

      out_stream = StringIO.new
      err_stream = StringIO.new
      main = described_class.new(out_stream, err_stream, argv: ['info', '-h'])

      expect(WifiWand::CommandLineInterface).to receive(:new) do |options, argv:|
        expect(options.help_requested).to be(true)
        expect(argv).to eq(%w[help info])
        mock_cli
      end

      expect(main.call).to eq(0)
      expect(out_stream.string).to eq('')
      expect(err_stream.string).to eq('')
    end
  end

  describe 'invalid option behavior' do
    it 'prints the option error with a help hint' do
      main = described_class.new(out_stream, err_stream, argv: ['--bananas'])

      expect(main.call).to eq(1)
      expect(err_stream.string).to include('Error: invalid option: --bananas')
      expect(err_stream.string).to include('Use -h or --help to see available options.')
    end
  end

  describe 'command argument validation' do
    [
      ['connect', 'Missing <network> argument.', 'Usage: wifiwand connect <network> [password]', []],
      ['forget', 'Missing <name1> argument.', 'Usage: wifiwand forget <name1> [name2 ...]', []],
      ['password', 'Missing <network-name> argument.', 'Usage: wifiwand password <network-name>', []],
      ['till', 'Missing <state> argument.', 'Usage: wifiwand till <state> [timeout_secs] [interval_secs]',
        [
          'States: wifi_on, wifi_off, associated, disassociated, internet_on, internet_off',
          "Examples: 'till wifi_off 20' or 'till internet_on 30 0.5'",
        ]],
    ].each do |command_name, missing_message, usage, extra_messages|
      it "returns a user-facing usage error when #{command_name} is missing a required operand" do
        out_stream = StringIO.new
        err_stream = StringIO.new
        main = described_class.new(out_stream, err_stream, argv: [command_name])

        expect(WifiWand).not_to receive(:create_model)

        expect(main.call).to eq(1)
        expect(err_stream.string).to include(missing_message)
        expect(err_stream.string).to include(usage)
        extra_messages.each { |message| expect(err_stream.string).to include(message) }
        expect(err_stream.string).to include("Use 'wifiwand help' or 'wifiwand -h' for help.")
        expect(err_stream.string).not_to include('wrong number of arguments')
        expect(out_stream.string).to eq('')
      end
    end
  end
end
