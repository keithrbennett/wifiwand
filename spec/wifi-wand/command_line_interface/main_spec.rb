# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi-wand/main')

describe WifiWand::Main do
  let(:out_stream) { StringIO.new }
  let(:err_stream) { StringIO.new }
  subject { described_class.new(out_stream, err_stream) }

  def parse_with_argv(*args)
    stub_const('ARGV', args)
    subject.parse_command_line
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

    it 'parses shell/interactive mode flags' do
      options = parse_with_argv('--shell')
      expect(options.interactive_mode).to be(true)
      
      options = parse_with_argv('-s')
      expect(options.interactive_mode).to be(true)
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

    it 'parses help flag and adds h to ARGV' do
      stub_const('ARGV', ['--help'])
      options = subject.parse_command_line
      expect(ARGV).to include('h')
    end

    it 'removes parsed options from ARGV' do
      stub_const('ARGV', ['-v', '--shell', '-p', 'wlan0', 'connect', 'TestNetwork'])
      subject.parse_command_line
      
      # OptionParser should remove the parsed flags, leaving just the command and args
      expect(ARGV).to eq(['connect', 'TestNetwork'])
    end

    it 'handles multiple flags together' do
      stub_const('ARGV', ['-v', '-s', '-p', 'eth0', '--output_format', 'j', 'info'])
      options = subject.parse_command_line
      
      expect(options.verbose).to be(true)
      expect(options.interactive_mode).to be(true) 
      expect(options.wifi_interface).to eq('eth0')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'prepends options from WIFIWAND_OPTS before CLI arguments' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose')
      stub_const('ARGV', ['info'])

      options = subject.parse_command_line

      expect(options.verbose).to be(true)
      expect(ARGV).to eq(['info'])
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
    
    before(:each) do
      # Mock the command line parsing to avoid complex setup
      allow(subject).to receive(:parse_command_line).and_return(OpenStruct.new(verbose: false, interactive_mode: false))
      # Mock CLI creation to avoid OS detection
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'creates CLI with parsed options and calls it' do
      options = OpenStruct.new(verbose: true, wifi_interface: 'wlan0')
      allow(subject).to receive(:parse_command_line).and_return(options)
      
      expect(WifiWand::CommandLineInterface).to receive(:new).with(options).and_return(mock_cli)
      expect(mock_cli).to receive(:call)
      
      subject.call
    end

    it 'handles and prints exceptions and exits with code 1' do
      allow(mock_cli).to receive(:call).and_raise(StandardError.new('Test error'))
      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to match(/Error:.*Test error/m)
    end

    it 'prints clean error messages without backtraces by default and exits with code 1' do
      ex = StandardError.new('Test error')
      allow(ex).to receive(:backtrace).and_return(['line1', 'line2', 'line3'])
      allow(mock_cli).to receive(:call).and_raise(ex)
      
      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to eq("Error: Test error\n")
    end

    it 'prints backtrace only in verbose mode and exits with code 1' do
      ex = StandardError.new('Test error')
      allow(ex).to receive(:backtrace).and_return(['line1', 'line2', 'line3'])
      allow(mock_cli).to receive(:call).and_raise(ex)
      
      # Mock verbose mode
      allow(subject).to receive(:parse_command_line).and_return(OpenStruct.new(verbose: true, interactive_mode: false))
      
      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to match(/Error: Test error/)
      expect(err_stream.string).to match(/Stack trace:/)
    end

    it 'succeeds when no exceptions occur' do
      expect(mock_cli).to receive(:call).and_return('success')
      subject.call
      expect(out_stream.string).to be_empty
    end
  end

  describe 'output format processors' do
    it 'creates JSON processor' do
      stub_const('ARGV', ['-o', 'j', 'info'])  # 'j' for json
      options = subject.parse_command_line
      
      processor = options.post_processor
      test_data = {'test' => 'value'}
      result = processor.call(test_data)
      
      expect(result).to be_a(String)
      expect(JSON.parse(result)).to eq(test_data)
    end

    it 'creates YAML processor' do
      stub_const('ARGV', ['-o', 'y', 'info'])  # 'y' for yaml
      options = subject.parse_command_line
      
      processor = options.post_processor
      test_data = {'test' => 'value'}
      result = processor.call(test_data)
      
      expect(result).to be_a(String)
      expect(YAML.load(result)).to eq(test_data)
    end

    it 'creates inspect processor' do
      stub_const('ARGV', ['-o', 'i', 'info'])  # 'i' for inspect
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = {'test' => 'value'}
      result = processor.call(test_data)

      expect(result).to eq(test_data.inspect)
    end

    it 'creates pretty JSON processor' do
      stub_const('ARGV', ['-o', 'k', 'info'])  # 'k' for pretty JSON
      options = subject.parse_command_line

      processor = options.post_processor
      test_data = {'test' => 'value'}
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
      test_data = {'test' => 'value'}
      result = processor.call(test_data)

      expect(result).to be_a(String)
      expect(result).to eq("#{test_data}\n")
    end
  end

  describe 'integration workflow' do
    let(:mock_cli) { double('CommandLineInterface') }
    
    before(:each) do
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'parses arguments and executes CLI with correct options' do
      stub_const('ARGV', ['-v', '--shell', '-p', 'wlan0', 'info'])
      
      expect(WifiWand::CommandLineInterface).to receive(:new) do |options|
        expect(options.verbose).to be(true)
        expect(options.interactive_mode).to be(true)
        expect(options.wifi_interface).to eq('wlan0')
        mock_cli
      end
      expect(mock_cli).to receive(:call)
      
      subject.call
    end

    it 'handles complete workflow with output formatting' do
      stub_const('ARGV', ['-o', 'j', 'info'])
      
      expect(WifiWand::CommandLineInterface).to receive(:new) do |options|
        expect(options.post_processor).to respond_to(:call)
        mock_cli
      end
      expect(mock_cli).to receive(:call)
      
      subject.call
    end
  end

  describe '#handle_error' do
    let(:mock_cli) { double('CommandLineInterface') }

    before(:each) do
      allow(subject).to receive(:parse_command_line).and_return(OpenStruct.new(verbose: false, interactive_mode: false))
      allow(WifiWand::CommandLineInterface).to receive(:new).and_return(mock_cli)
    end

    it 'handles OsCommandError with specific error message and exits with code 1' do
      ex = WifiWand::CommandExecutor::OsCommandError.new(1, 'a command', 'a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expected_output = <<~MESSAGE

        Error: a message
        Command failed: a command
        Exit code: 1
      MESSAGE

      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to eq(expected_output)
    end

    it 'handles WifiWand::Error with a simple error message and exits with code 1' do
      ex = WifiWand::Error.new('a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to eq("Error: a message\n")
    end

    it 'handles other errors with a simple error message and exits with code 1' do
      ex = StandardError.new('a message')
      allow(mock_cli).to receive(:call).and_raise(ex)

      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to eq("Error: a message\n")
    end

    it 'handles other errors with a stack trace in verbose mode and exits with code 1' do
      ex = StandardError.new('a message')
      allow(ex).to receive(:backtrace).and_return(['line 1', 'line 2'])
      allow(mock_cli).to receive(:call).and_raise(ex)
      allow(subject).to receive(:parse_command_line).and_return(OpenStruct.new(verbose: true, interactive_mode: false))

      expect { subject.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(err_stream.string).to match(/Error: a message/)
      expect(err_stream.string).to match(/Stack trace:/)
    end
  end

  describe 'help flag behavior' do
    it 'prints help without initializing the model and exits successfully' do
      # Ensure create_model is not called when help is requested
      expect(WifiWand).not_to receive(:create_model)

      stub_const('ARGV', ['--help'])
      out_stream = StringIO.new
      err_stream = StringIO.new
      main = described_class.new(out_stream, err_stream)

      expect { main.call }.not_to raise_error
      expect(out_stream.string).to include('Command Line Switches')
    end
  end
end
