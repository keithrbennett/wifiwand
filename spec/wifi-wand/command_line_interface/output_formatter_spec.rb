# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi-wand/command_line_interface')

describe WifiWand::CommandLineInterface::OutputFormatter do
  # Regex patterns for color code detection
  ANSI_COLOR_REGEX = /\e\[\d+m/
  GREEN_TEXT_REGEX = /\e\[32m.*\e\[0m/
  RED_TEXT_REGEX   = /\e\[31m.*\e\[0m/
  YELLOW_TEXT_REGEX = /\e\[33m.*\e\[0m/
  CYAN_TEXT_REGEX  = /\e\[36m.*\e\[0m/

  # Create a test class that includes the OutputFormatter module
  let(:test_class) do
    Class.new do
      include WifiWand::CommandLineInterface::OutputFormatter

      attr_accessor :options, :model

      def initialize(options = nil, model = nil)
        @options = options || OpenStruct.new
        @model = model
      end
    end
  end

  let(:mock_model) do
    double('model',
      wifi_on?: true,
      connected_network_name: 'TestNetwork',
      internet_tcp_connectivity?: true,
      dns_working?: true,
      connected_to_internet?: true
    )
  end

  let(:options) { OpenStruct.new(post_processor: nil) }
  subject { test_class.new(options, mock_model) }

  # Shared examples for colorization methods
  shared_examples 'colorization method' do |test_cases|
    test_cases[:tests].each do |description, data|
      it description do
        allow($stdout).to receive(:tty?).and_return(data[:tty])
        result = subject.public_send(test_cases[:method_name], data[:input])
        expect(result).to eq(data[:expected_output])

        # Verify color codes are present when expected (tty: true + colorizable) and absent otherwise
        expected_has_color = data[:tty] && data.fetch(:has_color, true)
        expect(result.match?(ANSI_COLOR_REGEX)).to eq(expected_has_color)
      end
    end
  end

  describe '#format_object' do
    let(:test_object) { { name: 'test', value: 123 } }

    it 'returns awesome_inspect formatted output' do
      result = subject.format_object(test_object)
      expect(result).to include('name', 'test', 'value', '123')
      expect(result).to be_a(String)
    end
  end

  describe '#colorize_text' do
    let(:text) { 'test text' }

    test_cases = {
      'colorizes text with red color when TTY'               => { color: :red,     expected_output: "\e[31mtest text\e[0m", tty: true },
      'colorizes text with green color when TTY'             => { color: :green,   expected_output: "\e[32mtest text\e[0m", tty: true },
      'colorizes text with yellow color when TTY'            => { color: :yellow,  expected_output: "\e[33mtest text\e[0m", tty: true },
      'colorizes text with blue color when TTY'              => { color: :blue,    expected_output: "\e[34mtest text\e[0m", tty: true },
      'colorizes text with cyan color when TTY'              => { color: :cyan,    expected_output: "\e[36mtest text\e[0m", tty: true },
      'colorizes text with magenta color when TTY'           => { color: :magenta, expected_output: "\e[35mtest text\e[0m", tty: true },
      'colorizes text with bold style when TTY'              => { color: :bold,    expected_output: "\e[1mtest text\e[0m",  tty: true },
      'returns plain text without color codes when not TTY' => { color: :red,     expected_output: 'test text',            tty: false },
      'returns plain text when no color is provided'        => { color: nil,      expected_output: 'test text',            tty: true }
    }

    test_cases.each do |description, data|
      it description do
        allow($stdout).to receive(:tty?).and_return(data[:tty])
        result = subject.colorize_text(text, data[:color])
        expect(result).to eq(data[:expected_output])
      end
    end
  end

  describe '#colorize_status' do
    include_examples 'colorization method', {
      method_name: :colorize_status,
      tests: {
        'colorizes "true" as green when TTY'                              => { input: 'true',         expected_output: "\e[32mtrue\e[0m",         tty: true },
        'colorizes "on" as green when TTY'                                => { input: 'on',           expected_output: "\e[32mon\e[0m",           tty: true },
        'colorizes "connected" as green when TTY'                         => { input: 'connected',    expected_output: "\e[32mconnected\e[0m",    tty: true },
        'colorizes "yes" as green when TTY'                               => { input: 'yes',          expected_output: "\e[32myes\e[0m",          tty: true },
        'colorizes "FALSE" as red (case insensitive) when TTY'            => { input: 'FALSE',        expected_output: "\e[31mFALSE\e[0m",        tty: true },
        'colorizes "false" as red when TTY'                               => { input: 'false',        expected_output: "\e[31mfalse\e[0m",        tty: true },
        'colorizes "off" as red when TTY'                                 => { input: 'off',          expected_output: "\e[31moff\e[0m",          tty: true },
        'colorizes "disconnected" as red when TTY'                        => { input: 'disconnected', expected_output: "\e[31mdisconnected\e[0m", tty: true },
        'colorizes "no" as red when TTY'                                  => { input: 'no',           expected_output: "\e[31mno\e[0m",           tty: true },
        'returns "unknown" unchanged (no word boundary match) when TTY'   => { input: 'unknown',      expected_output: 'unknown',                tty: true, has_color: false },
        'returns empty string unchanged when TTY'                         => { input: '',             expected_output: '',                       tty: true, has_color: false },
        'returns plain text for positive status when not TTY'             => { input: 'true',         expected_output: 'true',                   tty: false },
        'returns plain text for negative status when not TTY'             => { input: 'false',        expected_output: 'false',                  tty: false },
        'returns plain text for disconnected when not TTY'                => { input: 'disconnected', expected_output: 'disconnected',           tty: false }
      }
    }
  end

  describe '#colorize_network_name' do
    include_examples 'colorization method', {
      method_name: :colorize_network_name,
      tests: {
        'colorizes quoted network names in cyan when TTY'                => { input: 'Connected to "MyNetwork" successfully',     expected_output: "Connected to \e[36m\"MyNetwork\"\e[0m successfully", tty: true },
        'colorizes multiple quoted network names when TTY'               => { input: 'Networks: "Network1" and "Network2"',      expected_output: "Networks: \e[36m\"Network1\"\e[0m and \e[36m\"Network2\"\e[0m", tty: true },
        'does not colorize unquoted text when TTY'                       => { input: 'No quoted networks here',                   expected_output: 'No quoted networks here', tty: true, has_color: false },
        'handles empty quotes when TTY'                                  => { input: 'Empty network name: ""',                    expected_output: "Empty network name: \e[36m\"\"\e[0m", tty: true },
        'returns plain text for quoted network names when not TTY'       => { input: 'Connected to "MyNetwork" successfully',     expected_output: 'Connected to "MyNetwork" successfully', tty: false },
        'returns plain text for multiple quoted network names when not TTY' => { input: 'Networks: "Network1" and "Network2"',  expected_output: 'Networks: "Network1" and "Network2"', tty: false }
      }
    }
  end

  describe '#colorize_values' do
    include_examples 'colorization method', {
      method_name: :colorize_values,
      tests: {
        'colorizes percentages in blue when TTY'                     => { input: 'Signal strength: 85%',                       expected_output: "Signal strength: \e[34m85%\e[0m", tty: true },
        'colorizes IP addresses in blue when TTY'                    => { input: 'IP: 192.168.1.1',                            expected_output: "IP: \e[34m192.168.1.1\e[0m", tty: true },
        'colorizes standalone numbers in blue when TTY'              => { input: 'Channel: 6',                                 expected_output: "Channel: \e[34m6\e[0m", tty: true },
        'colorizes multiple values in the same text when TTY'        => { input: 'Signal: 75% on channel 11 at 192.168.1.1',  expected_output: "Signal: \e[34m75%\e[0m on channel \e[34m11\e[0m at \e[34m192.168.1.1\e[0m", tty: true },
        'does not colorize numbers that are part of words when TTY'  => { input: 'Network5G is fast',                          expected_output: 'Network5G is fast', tty: true, has_color: false },
        'returns plain text for percentages when not TTY'            => { input: 'Signal strength: 85%',                       expected_output: 'Signal strength: 85%', tty: false },
        'returns plain text for IP addresses when not TTY'           => { input: 'IP: 192.168.1.1',                            expected_output: 'IP: 192.168.1.1', tty: false },
        'returns plain text for multiple values when not TTY'        => { input: 'Signal: 75% on channel 11 at 192.168.1.1',  expected_output: 'Signal: 75% on channel 11 at 192.168.1.1', tty: false }
      }
    }
  end

  describe '#status_line' do
    let(:status_data) do
      {
        wifi_on: true,
        network_name: 'TestNetwork',
        internet_connected: true
      }
    end

    context 'when stdout is a TTY' do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      it 'contains all status components with appropriate colors' do
        result = subject.status_line(status_data)

        # Test logical content rather than exact formatting
        expect(result).to match(/WiFi.*YES/)
        expect(result).to match(/Network.*TestNetwork/)  # network_name is included in test data
        expect(result).to match(/Internet.*YES/)

        # Verify colorization is present
        expect(result).to match(GREEN_TEXT_REGEX)      # Green ON
        expect(result).to match(CYAN_TEXT_REGEX)       # Cyan network name
        expect(result).to match(GREEN_TEXT_REGEX)     # Green YES statuses
      end

      it 'omits network field when not present in status data' do
        data_without_network = {
          wifi_on: true,
          internet_connected: true
        }
        result = subject.status_line(data_without_network)

        # Should not include Network field
        expect(result).to match(/WiFi.*YES/)
        expect(result).not_to match(/Network/)
        expect(result).to match(/Internet.*YES/)
      end

      hash_key_map = {
        wifi_on?: :wifi_on,
        connected_network_name: :network_name,
        connected_to_internet?: :internet_connected
      }

      {
        'WiFi off'         => { mock_method: :wifi_on?,                return_value: false, expected_pattern: /WiFi.*NO/,      expected_color: RED_TEXT_REGEX },
        'no network'       => { mock_method: :connected_network_name,  return_value: nil,   expected_pattern: /Network.*none/, expected_color: YELLOW_TEXT_REGEX },
        'Internet failure' => { mock_method: :connected_to_internet?,  return_value: false, expected_pattern: /Internet.*NO/,  expected_color: RED_TEXT_REGEX }
      }.each do |scenario, config|
        it "displays error status when #{scenario}" do
          data = status_data.clone
          target_key = hash_key_map[config[:mock_method]]
          new_value = config[:return_value]
          data[target_key] = new_value

          result = subject.status_line(data)

          expect(result).to match(config[:expected_pattern])
          expect(result).to match(config[:expected_color])
        end
      end

      it 'returns fallback message when model raises exception' do
        result = subject.status_line(nil)

        expect(result).to match(/WiFi.*status unavailable/)
        expect(result).to match(YELLOW_TEXT_REGEX) # Yellow warning
      end
    end

    context 'when stdout is not a TTY' do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it 'contains all status components without color codes' do
        result = subject.status_line(status_data)

        # Test logical content
        expect(result).to match(/WiFi.*YES/)
        expect(result).to match(/Network.*TestNetwork/)  # network_name is included in test data
        expect(result).to match(/Internet.*YES/)

        # Verify no color codes
        expect(result).not_to match(ANSI_COLOR_REGEX)
      end

      it 'omits network field when not present in status data' do
        data_without_network = {
          wifi_on: true,
          internet_connected: true
        }
        result = subject.status_line(data_without_network)

        # Should not include Network field
        expect(result).to match(/WiFi.*YES/)
        expect(result).not_to match(/Network/)
        expect(result).to match(/Internet.*YES/)
        expect(result).not_to match(ANSI_COLOR_REGEX)
      end

      it 'shows error conditions without color codes' do
        data = status_data.clone
        data[:wifi_on] = false
        result = subject.status_line(data)

        expect(result).to match(/WiFi.*NO/)
        expect(result).not_to match(ANSI_COLOR_REGEX)
      end

      it 'shows fallback status without color codes' do
        result = subject.status_line(nil)

        expect(result).to match(/WiFi.*status unavailable/)
        expect(result).not_to match(ANSI_COLOR_REGEX)
      end
    end
  end

  describe '#post_process' do
    let(:test_object) { { key: 'value' } }

    context 'when post_processor is set' do
      let(:processor) { ->(obj) { obj.to_s.upcase } }
      let(:options) { OpenStruct.new(post_processor: processor) }

      it 'applies the post processor' do
        result = subject.post_process(test_object)
        # Accept both old Ruby format and new Ruby format
        expect(result).to eq(%q{{:KEY=>"VALUE"}}).or eq(%q{{KEY: "VALUE"}})
      end
    end

    context 'when post_processor is nil' do
      it 'returns the object unchanged' do
        result = subject.post_process(test_object)
        expect(result).to eq(test_object)
      end
    end
  end

  describe '#post_processor' do
    context 'when options has post_processor' do
      let(:processor) { ->(obj) { obj.to_s } }
      let(:options) { OpenStruct.new(post_processor: processor) }

      it 'returns the post_processor from options' do
        expect(subject.post_processor).to eq(processor)
      end
    end

    context 'when options has no post_processor' do
      it 'returns nil' do
        expect(subject.post_processor).to be_nil
      end
    end
  end
end
