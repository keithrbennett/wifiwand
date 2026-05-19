# frozen_string_literal: true

require_relative('../spec_helper')
require_relative('../../lib/wifi_wand/command_line_parser')

describe WifiWand::CommandLineParser do
  let(:err_stream) { StringIO.new }

  def parse_with_argv(*args)
    described_class.new(args, ENV, err_stream).parse
  end

  describe '#parse' do
    it 'parses verbose flags' do
      options = parse_with_argv('--verbose', 'true', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('-v', 'yes', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('-vtrue', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('--verbose=true', 'info')
      expect(options.verbose).to be(true)

      options = parse_with_argv('--verbose=false', 'info')
      expect(options.verbose).to be(false)

      options = parse_with_argv('-vfalse', 'info')
      expect(options.verbose).to be(false)
    end

    it 'defaults verbose to nil when not specified' do
      options = parse_with_argv('info')
      expect(options.verbose).to be_nil
    end

    it 'parses utc flags with boolean values' do
      options = parse_with_argv('--utc', 'true', 'info')
      expect(options.utc).to be(true)

      options = parse_with_argv('-u', 'yes', 'info')
      expect(options.utc).to be(true)

      options = parse_with_argv('--utc=false', 'info')
      expect(options.utc).to be(false)

      options = parse_with_argv('-ufalse', 'info')
      expect(options.utc).to be(false)
    end

    it 'parses utc flags after the command' do
      options = parse_with_argv('info', '-u', 'yes')

      expect(options.utc).to be(true)
      expect(options.argv).to eq(['info'])
    end

    it 'parses false utc values after the command' do
      options = parse_with_argv('info', '--utc=false')

      expect(options.utc).to be(false)
      expect(options.argv).to eq(['info'])
    end

    it 'uses the last occurrence when an option is repeated' do
      options = parse_with_argv('-u', 'yes', '--utc=false', 'info')

      expect(options.utc).to be(false)
      expect(options.argv).to eq(['info'])
    end

    {
      true  => %w[true yes y t +],
      false => %w[false no n f -],
    }.each do |expected, values|
      values.each do |value|
        {
          '--utc'     => :utc,
          '--verbose' => :verbose,
        }.each do |option, attribute|
          it "parses #{option} #{value.inspect} as #{expected}" do
            options = parse_with_argv(option, value, 'info')
            expect(options.public_send(attribute)).to be(expected)
          end
        end
      end
    end

    %w[on off 1 0].each do |value|
      %w[--utc --verbose].each do |option|
        it "rejects unsupported #{option} boolean value #{value.inspect}" do
          expect do
            parse_with_argv(option, value, 'info')
          end.to raise_error(WifiWand::ConfigurationError) { |error|
            expect(error.message).to include('invalid argument')
            expect(error.message).to include('Use -h or --help to see available options.')
          }
        end
      end
    end

    it 'does not treat a following command as an implicit utc value' do
      expect do
        described_class.new(%w[-u connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('invalid argument: -u connect')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    it 'does not treat a following command as an implicit verbose value' do
      expect do
        described_class.new(%w[-v connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('invalid argument: -v connect')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    %w[-v --verbose].each do |option|
      it "raises a configuration error when #{option} has no value" do
        expect do
          described_class.new([option], ENV, err_stream).parse
        end.to raise_error(WifiWand::ConfigurationError) { |error|
          expect(error.message).to include("missing argument: #{option}")
          expect(error.message).to include('Use -h or --help to see available options.')
        }
      end
    end

    it 'defaults utc to nil when not specified' do
      options = parse_with_argv('info')
      expect(options.utc).to be_nil
    end

    it 'leaves shell in argv for normal command dispatch' do
      options = parse_with_argv('shell')
      expect(options.interactive_mode).to be_nil
      expect(options.argv).to eq(['shell'])
    end

    it 'parses wifi interface options' do
      options = parse_with_argv('--wifi-interface', 'wlan0', 'info')
      expect(options.wifi_interface).to eq('wlan0')

      options = parse_with_argv('-p', 'en0', 'info')
      expect(options.wifi_interface).to eq('en0')
    end

    it 'parses output format options' do
      options = parse_with_argv('--output-format', 'j', 'info')
      expect(options.post_processor).to respond_to(:call)

      options = parse_with_argv('--out', 'j', 'info')
      expect(options.post_processor).to respond_to(:call)

      options = parse_with_argv('--output_format', 'j', 'info')
      expect(options.post_processor).to respond_to(:call)

      options = parse_with_argv('-o', 'y', 'info')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'handles invalid output format' do
      expect do
        described_class.new(['-o', 'z', 'info'], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /Invalid output format 'z'/)
      expect(err_stream.string).to be_empty
    end

    it 'handles empty output format with a configuration error' do
      expect do
        described_class.new(['-o', '', 'info'], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /Invalid output format ''/)
      expect(err_stream.string).to be_empty
    end

    it 'handles unrecognized flags' do
      expect do
        described_class.new(['--invalid-flag'], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('invalid option: --invalid-flag')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    it 'normalizes --help into the help command' do
      options = described_class.new(['--help'], ENV, err_stream).parse
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(['help'])
    end

    it 'normalizes leading help flags combined with a command into the help command' do
      options = described_class.new(['-h', 'info'], ENV, err_stream).parse
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(%w[help info])
    end

    it 'normalizes trailing help flags after a command into command help' do
      options = described_class.new(['info', '-h'], ENV, err_stream).parse
      expect(options.help_requested).to be(true)
      expect(options.argv).to eq(%w[help info])
    end

    it 'parses version flags' do
      options = parse_with_argv('--version')
      expect(options.version_requested).to be(true)

      options = parse_with_argv('-V')
      expect(options.version_requested).to be(true)
    end

    it 'returns command argv without the parsed options' do
      options = described_class.new(['-v', 'true', '-p', 'wlan0', 'connect', 'TestNetwork'], ENV,
        err_stream).parse
      expect(options.argv).to eq(%w[connect TestNetwork])
    end

    it 'returns command argv without parsed options that appear after the command' do
      options = described_class.new(['info', '-u', 'yes'], ENV, err_stream).parse

      expect(options.utc).to be(true)
      expect(options.argv).to eq(['info'])
    end

    it 'rejects utc before connect' do
      expect do
        described_class.new(%w[-u yes connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for connect/)
    end

    it 'rejects utc after connect' do
      expect do
        described_class.new(%w[connect TestNetwork -u yes], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for connect/)
    end

    it 'rejects utc for commands without timestamped output' do
      expect do
        described_class.new(%w[status -u yes], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for status/)
    end

    it 'rejects output formatting for commands without structured output' do
      expect do
        described_class.new(%w[connect TestNetwork -o json], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--output-format is not valid for connect/)
    end

    it 'rejects output formatting for qr terminal output' do
      expect do
        described_class.new(%w[-o json qr], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--output-format is not valid for qr stdout output/)
    end

    it 'accepts output formatting for qr file output' do
      options = described_class.new(%w[-o json qr wifi.png], ENV, err_stream).parse

      expect(options.post_processor).to respond_to(:call)
      expect(options.argv).to eq(%w[qr wifi.png])
    end

    it 'rejects compact and abbreviated invocation options from the command line' do
      expect do
        described_class.new(%w[-ufalse connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for connect/)

      expect do
        described_class.new(%w[-oj connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--output-format is not valid for connect/)

      expect do
        described_class.new(%w[-pen0 public_ip], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--wifi-interface is not valid for public_ip/)

      expect do
        described_class.new(%w[--out j connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--output-format is not valid for connect/)

      expect do
        described_class.new(%w[--output-f j connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--output-format is not valid for connect/)
    end

    it 'rejects wifi interface selection for commands that do not use WiFi model behavior' do
      expect do
        described_class.new(%w[public_ip -p en0], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--wifi-interface is not valid for public_ip/)
    end

    it 'rejects positional command arguments before the command' do
      expect do
        described_class.new(%w[TestNetwork connect], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /Unexpected argument\(s\) before connect: TestNetwork/)
    end

    it 'rejects positional command arguments before the command when options are mixed in' do
      expect do
        described_class.new(%w[TestNetwork -v false secret connect], ENV, err_stream).parse
      end.to raise_error(
        WifiWand::ConfigurationError,
        /Unexpected argument\(s\) before connect: TestNetwork, secret/
      )
    end

    it 'parses log interval after the log command' do
      options = described_class.new(%w[log --interval 5], ENV, err_stream).parse

      expect(options.command_options).to eq(interval: 5.0)
      expect(options.argv).to eq(['log'])
    end

    it 'parses log interval before the log command' do
      options = described_class.new(%w[--interval 5 log], ENV, err_stream).parse

      expect(options.command_options).to eq(interval: 5.0)
      expect(options.argv).to eq(['log'])
    end

    it 'parses inline log interval before the log command' do
      options = described_class.new(%w[--interval=5 log], ENV, err_stream).parse

      expect(options.command_options).to eq(interval: 5.0)
      expect(options.argv).to eq(['log'])
    end

    it 'parses log interval with invocation options around the command' do
      options = described_class.new(%w[--interval 5 -u yes log], ENV, err_stream).parse

      expect(options.utc).to be(true)
      expect(options.command_options).to eq(interval: 5.0)
      expect(options.argv).to eq(['log'])
    end

    it 'parses log file destination after the log command' do
      options = described_class.new(%w[log --file /tmp/events.log], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              '/tmp/events.log'
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses log default file destination after the log command' do
      options = described_class.new(%w[log --file], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              WifiWand::LogFileManager::DEFAULT_LOG_FILE
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses log default file destination before the log command' do
      options = described_class.new(%w[--file log], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              WifiWand::LogFileManager::DEFAULT_LOG_FILE
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses custom log file destination before the log command' do
      options = described_class.new(%w[--file /tmp/events.log log], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              '/tmp/events.log'
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses pre-command log file destination that matches another command alias' do
      options = described_class.new(%w[--file status log], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              'status'
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses repeated pre-command log file destinations' do
      options = described_class.new(%w[--file /tmp/first.log --file /tmp/second.log log], ENV,
        err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              '/tmp/second.log'
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses log stdout destination after the log command' do
      options = described_class.new(%w[log --file /tmp/events.log --stdout], ENV, err_stream).parse

      expect(options.command_options).to include(
        file_destination_requested: true,
        log_file_path:              '/tmp/events.log',
        stdout_explicit:            true
      )
      expect(options.argv).to eq(['log'])
    end

    it 'parses log stdout without a file destination' do
      options = described_class.new(%w[log --stdout], ENV, err_stream).parse

      expect(options.command_options).to include(stdout_explicit: true)
      expect(options.argv).to eq(['log'])
    end

    it 'rejects log interval for other commands' do
      expect do
        described_class.new(%w[info --interval 5], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--interval is not valid for info/)
    end

    it 'rejects inline log interval for other commands' do
      expect do
        described_class.new(%w[info --interval=5], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--interval is not valid for info/)
    end

    it 'rejects log interval before other commands' do
      expect do
        described_class.new(%w[--interval 5 info], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--interval is not valid for info/)
    end

    it 'raises a configuration error when log interval is not numeric' do
      expect do
        described_class.new(%w[log --interval bad_value], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('invalid argument')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    it 'raises a configuration error when log interval is missing' do
      expect do
        described_class.new(%w[log --interval], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('missing argument: --interval')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    it 'raises a configuration error when log stdout has a needless value' do
      expect do
        described_class.new(%w[log --stdout=bad], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('needless argument: --stdout=bad')
        expect(error.message).to include('Use -h or --help to see available options.')
      }
    end

    it 'rejects log file options for other commands' do
      expect do
        described_class.new(%w[info --file /tmp/events.log], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--file is not valid for info/)
    end

    it 'preserves positional arguments after the option terminator' do
      options = described_class.new(%w[connect -- -NetworkStartingWithDash], ENV, err_stream).parse

      expect(options.argv).to eq(%w[connect -NetworkStartingWithDash])
    end

    it 'validates invocation options when the command appears after the option terminator' do
      expect do
        described_class.new(%w[-u true -- connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for connect/)
    end

    it 'handles multiple flags together' do
      options = described_class.new(['-v', 'true', '-p', 'eth0', '--output-format', 'j', 'info'], ENV,
        err_stream).parse
      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.post_processor).to respond_to(:call)
    end

    it 'handles shell command alongside wifi interface selection' do
      options = described_class.new(%w[-v true -p eth0 shell], ENV, err_stream).parse

      expect(options.verbose).to be(true)
      expect(options.wifi_interface).to eq('eth0')
      expect(options.interactive_mode).to be_nil
      expect(options.argv).to eq(['shell'])
    end

    it 'allows shell startup to inherit utc configuration' do
      options = described_class.new(%w[-u true shell], ENV, err_stream).parse

      expect(options.utc).to be(true)
      expect(options.argv).to eq(['shell'])
    end

    it 'lets shell startup report its own output format error' do
      options = described_class.new(%w[-o json shell], ENV, err_stream).parse

      expect(options.post_processor).to respond_to(:call)
      expect(options.argv).to eq(['shell'])
    end

    it 'handles ropen command alongside wifi interface selection' do
      options = described_class.new(%w[-p eth0 ropen ipw], ENV, err_stream).parse

      expect(options.wifi_interface).to eq('eth0')
      expect(options.argv).to eq(%w[ropen ipw])
    end

    it 'prepends options from WIFIWAND_OPTS before CLI arguments' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose true')

      options = described_class.new(['info'], ENV, err_stream).parse

      expect(options.verbose).to be(true)
      expect(options.argv).to eq(['info'])
    end

    it 'does not reject help when WIFIWAND_OPTS contains model options' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('-p en0 -u false -o j')

      options = described_class.new(['help'], ENV, err_stream).parse

      expect(options.wifi_interface).to eq('en0')
      expect(options.utc).to be(false)
      expect(options.post_processor).to respond_to(:call)
      expect(options.argv).to eq(['help'])
    end

    it 'does not reject quit when WIFIWAND_OPTS contains model options' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('-p en0 -u false -o j')

      options = described_class.new(['quit'], ENV, err_stream).parse

      expect(options.wifi_interface).to eq('en0')
      expect(options.utc).to be(false)
      expect(options.post_processor).to respond_to(:call)
      expect(options.argv).to eq(['quit'])
    end

    it 'ignores irrelevant invocation options from WIFIWAND_OPTS' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--utc true --output-format j')

      options = described_class.new(%w[connect TestNetwork], ENV, err_stream).parse

      expect(options.utc).to be(true)
      expect(options.post_processor).to respond_to(:call)
      expect(options.argv).to eq(%w[connect TestNetwork])
    end

    it 'ignores environment-sourced output formatting for qr terminal output' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--output-format j')

      options = described_class.new(%w[qr], ENV, err_stream).parse

      expect(options.post_processor).to respond_to(:call)
      expect(options.invocation_option_sources).to include(output_format: :environment)
      expect(options.argv).to eq(%w[qr])
    end

    it 'does not treat the option terminator as an explicit invocation option' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--utc true')

      options = described_class.new(%w[-- connect TestNetwork], ENV, err_stream).parse

      expect(options.utc).to be(true)
      expect(options.argv).to eq(%w[connect TestNetwork])
    end

    it 'still rejects irrelevant invocation options from the command line' do
      expect do
        described_class.new(%w[--utc true connect TestNetwork], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /--utc is not valid for connect/)
    end

    it 'identifies invalid command-specific options from WIFIWAND_OPTS' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--interval 5')

      parser = described_class.new(%w[info], ENV, err_stream)

      expect do
        parser.parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('--interval is not valid for info.')
        expect(error.message).to include('This option came from WIFIWAND_OPTS.')
      }
      expect(parser.send(:option_source_for, '--interval')).to be(:environment)
    end

    it 'identifies invalid command-specific options with inline values from WIFIWAND_OPTS' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--interval=5')

      expect do
        described_class.new(%w[info], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError) { |error|
        expect(error.message).to include('--interval is not valid for info.')
        expect(error.message).to include('This option came from WIFIWAND_OPTS.')
      }
    end

    it 'rejects unknown options from WIFIWAND_OPTS' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--bananas')

      expect do
        described_class.new(%w[info], ENV, err_stream).parse
      end.to raise_error(WifiWand::ConfigurationError, /invalid option: --bananas/)
    end

    it 'allows explicit command-line flags to override WIFIWAND_OPTS defaults' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WIFIWAND_OPTS').and_return('--verbose true --wifi-interface en0')

      options = described_class.new(['--verbose', 'false', '--wifi-interface', 'en1', 'info'], ENV,
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
      input = ['-v', 'true', '-p', 'wlan0', 'connect', 'TestNetwork']
      original = input.dup
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(original)
    end

    it 'does not mutate the argv array when parsing shell command' do
      input = ['-v', 'true', 'shell']
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(['-v', 'true', 'shell'])
    end

    it 'does not mutate the argv array when help is requested' do
      input = ['-h', 'info']
      described_class.new(input, ENV, err_stream).parse
      expect(input).to eq(['-h', 'info'])
    end
  end

  describe 'output format processors' do
    {
      'a' => 'amazing print',
      'i' => 'inspect',
      'j' => 'JSON',
      'J' => 'pretty JSON',
      'p' => 'puts',
      'P' => 'pretty print',
      'y' => 'YAML',
    }.each do |format_code, format_name|
      it "correctly formats as #{format_name}" do
        options = parse_with_argv('-o', format_code, 'info')
        result = options.post_processor.call({ 'test' => 'value' })

        case format_code
        when 'a'
          expect(strip_ansi(result)).to include('"test" => "value"')
        when 'i'
          expect(result).to eq({ 'test' => 'value' }.inspect)
        when 'j'
          expect(result).to eq('{"test":"value"}')
        when 'J'
          expect(result).to eq(<<~JSON.chomp)
            {
              "test": "value"
            }
          JSON
        when 'p', 'P'
          expect(result).to end_with("\n")
          expect(result.chomp).to match(/\{"test"\s*=>\s*"value"\}/)
        when 'y'
          expect(result).to eq(<<~YAML)
            ---
            test: value
          YAML
        else
          raise "No assertion defined for format code #{format_code.inspect}"
        end
      end
    end
  end
end
