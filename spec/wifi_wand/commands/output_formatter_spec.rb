# frozen_string_literal: true

require_relative('../../spec_helper')
require_relative('../../../lib/wifi_wand/command_line_interface')

describe WifiWand::Commands::OutputFormatter do
  subject { test_class.new(options, mock_model) }

  let(:ansi_color_regex) { /\e\[\d+m/ }
  let(:green_text_regex) { /\e\[32m.*\e\[0m/ }
  let(:red_text_regex) { /\e\[31m.*\e\[0m/ }
  let(:yellow_text_regex) { /\e\[33m.*\e\[0m/ }
  let(:blue_text_regex) { /\e\[34m.*\e\[0m/ }
  let(:bright_blue_text_regex) { /\e\[94m.*\e\[0m/ }
  let(:cyan_text_regex) { /\e\[36m.*\e\[0m/ }
  let(:status_line_hash_key_map) do
    {
      wifi_on?:                    :wifi_on,
      dns_working?:                :dns_working,
      connected_network_name:      :network_name,
      internet_connectivity_state: :internet_state,
    }.freeze
  end

  let(:test_class) do
    Class.new do
      include WifiWand::Commands::OutputFormatter

      attr_accessor :options, :model, :out_stream

      def initialize(options = nil, model = nil)
        @options = options || WifiWand::CommandLineOptions.new
        @model = model
        @out_stream = StringIO.new
      end
    end
  end

  let(:mock_model) do
    double('model',
      wifi_on?:                    true,
      connected_network_name:      'TestNetwork',
      internet_tcp_connectivity?:  true,
      dns_working?:                true,
      internet_connectivity_state: :reachable
    )
  end

  let(:options) { WifiWand::CommandLineOptions.new(post_processor: nil) }

  # Shared examples for colorization methods
  shared_examples 'colorization method' do |test_cases|
    test_cases[:tests].each do |data|
      it data[:name] do
        allow(subject.out_stream).to receive(:tty?).and_return(data[:tty])
        result = subject.public_send(test_cases[:method_name], data[:input])
        expect(result).to eq(data[:expected_output])

        # Verify color codes are present when expected (tty: true + colorizable) and absent otherwise
        expected_has_color = data[:tty] && (data[:has_color] != false)
        expect(result.match?(ansi_color_regex)).to eq(expected_has_color)
      end
    end
  end

  describe '#format_object' do
    let(:test_object) { { name: 'test', value: 123 } }

    it 'returns ai formatted output' do
      result = subject.format_object(test_object)
      expect(result).to include('name', 'test', 'value', '123')
      expect(result).to be_a(String)
    end

    it 'formats Time values as local ISO8601 timestamps by default without mutating the object' do
      previous_tz = ENV.fetch('TZ', nil)
      ENV['TZ'] = 'America/New_York'
      timestamp = Time.utc(2026, 5, 17, 11, 3, 50)
      object = { timestamp: timestamp }
      expected_timestamp = timestamp.getlocal.iso8601

      result = subject.format_object(object)

      expect(result).to include(expected_timestamp)
      expect(object[:timestamp]).to equal(timestamp)
      expect(timestamp).to be_utc
    ensure
      previous_tz.nil? ? ENV.delete('TZ') : ENV['TZ'] = previous_tz
    end

    it 'formats Time values as UTC ISO8601 timestamps when utc is enabled' do
      utc_options = WifiWand::CommandLineOptions.new(post_processor: nil, utc: true)
      formatter = test_class.new(utc_options, mock_model)
      timestamp = Time.new(2026, 5, 17, 18, 3, 50, '+07:00')

      result = formatter.format_object({ timestamp: timestamp })

      expect(result).to include('2026-05-17T11:03:50Z')
      expect(timestamp.utc_offset).to eq(7 * 60 * 60)
    end
  end

  describe '#colorize_text' do
    let(:text) { 'test text' }

    test_cases = [
      ['colorizes text with red color when TTY',              :red,     "\e[31mtest text\e[0m", true],
      ['colorizes text with green color when TTY',            :green,   "\e[32mtest text\e[0m", true],
      ['colorizes text with yellow color when TTY',           :yellow,  "\e[33mtest text\e[0m", true],
      ['colorizes text with blue color when TTY',             :blue,    "\e[34mtest text\e[0m", true],
      ['colorizes text with bright blue color when TTY',      :bright_blue, "\e[94mtest text\e[0m", true],
      ['colorizes text with cyan color when TTY',             :cyan,    "\e[36mtest text\e[0m", true],
      ['colorizes text with magenta color when TTY',          :magenta, "\e[35mtest text\e[0m", true],
      ['colorizes text with bold style when TTY',             :bold,    "\e[1mtest text\e[0m",  true],
      ['returns plain text without color codes when not TTY', :red,     'test text',            false],
      ['returns plain text when no color is provided',        nil,      'test text',            true],
    ].map { |name, color, expected_output, tty| { name:, color:, expected_output:, tty: } }

    test_cases.each do |data|
      it data[:name] do
        allow(subject.out_stream).to receive(:tty?).and_return(data[:tty])
        result = subject.colorize_text(text, data[:color])
        expect(result).to eq(data[:expected_output])
      end
    end
  end

  describe '#colorize_status' do
    it_behaves_like 'colorization method', {
      method_name: :colorize_status,
      tests:       [
        [
          'colorizes "true" as green when TTY',
          'true',
          "\e[32mtrue\e[0m",
          true,
        ],
        [
          'colorizes "on" as green when TTY',
          'on',
          "\e[32mon\e[0m",
          true,
        ],
        [
          'colorizes "connected" as green when TTY',
          'connected',
          "\e[32mconnected\e[0m",
          true,
        ],
        [
          'colorizes "yes" as green when TTY',
          'yes',
          "\e[32myes\e[0m",
          true,
        ],
        [
          'colorizes "FALSE" as red (case insensitive) when TTY',
          'FALSE',
          "\e[31mFALSE\e[0m",
          true,
        ],
        [
          'colorizes "false" as red when TTY',
          'false',
          "\e[31mfalse\e[0m",
          true,
        ],
        [
          'colorizes "off" as red when TTY',
          'off',
          "\e[31moff\e[0m",
          true,
        ],
        [
          'colorizes "disconnected" as red when TTY',
          'disconnected',
          "\e[31mdisconnected\e[0m",
          true,
        ],
        [
          'colorizes "no" as red when TTY',
          'no',
          "\e[31mno\e[0m",
          true,
        ],
        [
          'returns "unknown" unchanged (no word boundary match) when TTY',
          'unknown',
          'unknown',
          true, false
        ],
        [
          'returns empty string unchanged when TTY',
          '',
          '',
          true, false
        ],
        [
          'returns plain text for positive status when not TTY',
          'true',
          'true',
          false,
        ],
        [
          'returns plain text for negative status when not TTY',
          'false',
          'false',
          false,
        ],
        [
          'returns plain text for disconnected when not TTY',
          'disconnected',
          'disconnected',
          false,
        ],
      ].map do |name, input, expected_output, tty, has_color|
        { name:, input:, expected_output:, tty:, has_color: }
      end,
    }
  end

  describe '#colorize_network_name' do
    it_behaves_like 'colorization method', {
      method_name: :colorize_network_name,
      tests:       [
        [
          'colorizes quoted network names in cyan when TTY',
          'Connected to "MyNetwork" successfully',
          "Connected to \e[36m\"MyNetwork\"\e[0m successfully",
          true,
        ],
        [
          'colorizes multiple quoted network names when TTY',
          'Networks: "Network1" and "Network2"',
          "Networks: \e[36m\"Network1\"\e[0m and \e[36m\"Network2\"\e[0m",
          true,
        ],
        [
          'does not colorize unquoted text when TTY',
          'No quoted networks here',
          'No quoted networks here',
          true, false
        ],
        [
          'handles empty quotes when TTY',
          'Empty network name: ""',
          "Empty network name: \e[36m\"\"\e[0m",
          true,
        ],
        [
          'returns plain text for quoted network names when not TTY',
          'Connected to "MyNetwork" successfully',
          'Connected to "MyNetwork" successfully',
          false,
        ],
        [
          'returns plain text for multiple quoted network names when not TTY',
          'Networks: "Network1" and "Network2"',
          'Networks: "Network1" and "Network2"',
          false,
        ],
      ].map do |name, input, expected_output, tty, has_color|
        { name:, input:, expected_output:, tty:, has_color: }
      end,
    }
  end

  describe '#colorize_values' do
    it_behaves_like 'colorization method', {
      method_name: :colorize_values,
      tests:       [
        [
          'colorizes percentages in bright blue when TTY',
          'Signal strength: 85%',
          "Signal strength: \e[94m85%\e[0m",
          true,
        ],
        [
          'colorizes IP addresses in bright blue when TTY',
          'IP: 192.168.1.1',
          "IP: \e[94m192.168.1.1\e[0m",
          true,
        ],
        [
          'colorizes standalone numbers in bright blue when TTY',
          'Channel: 6',
          "Channel: \e[94m6\e[0m",
          true,
        ],
        [
          'colorizes multiple values in the same text when TTY',
          'Signal: 75% on channel 11 at 192.168.1.1',
          "Signal: \e[94m75%\e[0m on channel \e[94m11\e[0m at \e[94m192.168.1.1\e[0m",
          true,
        ],
        [
          'colorizes negative numbers in bright blue when TTY',
          'Signal quality: -65 dBm',
          "Signal quality: \e[94m-65\e[0m dBm",
          true,
        ],
        [
          'does not colorize numbers that are part of words when TTY',
          'Network5G is fast',
          'Network5G is fast',
          true, false
        ],
        [
          'returns plain text for percentages when not TTY',
          'Signal strength: 85%',
          'Signal strength: 85%',
          false,
        ],
        [
          'returns plain text for IP addresses when not TTY',
          'IP: 192.168.1.1',
          'IP: 192.168.1.1',
          false,
        ],
        [
          'returns plain text for multiple values when not TTY',
          'Signal: 75% on channel 11 at 192.168.1.1',
          'Signal: 75% on channel 11 at 192.168.1.1',
          false,
        ],
      ].map do |name, input, expected_output, tty, has_color|
        { name:, input:, expected_output:, tty:, has_color: }
      end,
    }
  end

  describe '#status_line' do
    let(:status_data) do
      {
        wifi_on:                       true,
        dns_working:                   true,
        network_name:                  'TestNetwork',
        internet_state:                :reachable,
        internet_check_complete:       true,
        captive_portal_login_required: :no,
      }
    end

    context 'when stdout is a TTY' do
      before { allow(subject.out_stream).to receive(:tty?).and_return(true) }

      it 'contains all status components with appropriate colors' do
        result = subject.status_line(status_data)

        # Test logical content rather than exact formatting
        expect(result).to match(/WiFi.*ON/)
        expect(result).to match(/WiFi Network.*TestNetwork/)  # network_name is included in test data
        expect(result).to match(/DNS.*YES/)
        expect(result).to match(/Internet.*YES/)

        # Verify colorization is present
        expect(result).to match(green_text_regex)      # Green ON
        expect(result).to match(cyan_text_regex)       # Cyan network name
        expect(result).to match(green_text_regex)     # Green YES statuses
      end

      {
        'WiFi off'         => [:wifi_on?, false, /WiFi.*OFF/, :red_text_regex],
        'no network'       => [:connected_network_name, nil, /WiFi Network.*none/, :yellow_text_regex],
        'DNS failure'      => [:dns_working?, false, /DNS.*NO/, :red_text_regex],
        'Internet failure' => [:internet_connectivity_state, :unreachable, /Internet.*NO/, :red_text_regex],
      }.each do |scenario, (mock_method, return_value, expected_pattern, expected_color_method)|
        it "displays error status when #{scenario}" do
          data = status_data.clone
          target_key = status_line_hash_key_map[mock_method]
          data[target_key] = return_value

          result = subject.status_line(data)

          expect(result).to match(expected_pattern)
          expect(result).to match(public_send(expected_color_method))
        end
      end

      it 'returns fallback message when model raises exception' do
        result = subject.status_line(nil)

        expect(result).to match(/WiFi.*status unavailable/)
        expect(result).to match(yellow_text_regex) # Yellow warning
      end

      it 'shows SSID unavailable when connected is true and the SSID is nil' do
        data = status_data.merge(connected: true, network_name: nil)

        result = subject.status_line(data)

        expect(result).to match(/WiFi Network.*SSID unavailable/)
        expect(result).to match(yellow_text_regex)
      end

      it 'appends signal quality after a connected network name' do
        data = status_data.merge(
          connected:      true,
          signal_quality: WifiWand::SignalQuality.new(value: -65, unit: :dbm)
        )

        result = subject.status_line(data)

        expect(result).to include('TestNetwork')
        expect(result).to match(/WiFi Network.*-65.*dBm/)
        expect(result).to match(bright_blue_text_regex)
      end

      it 'shows UNKNOWN when network identity is indeterminate after completion' do
        data = status_data.merge(connected: nil, network_name: nil)

        result = subject.status_line(data)

        expect(result).to match(/WiFi Network.*UNKNOWN/)
        expect(result).to match(yellow_text_regex)
      end

      context 'when captive portal is detected' do
        it 'does not show captive portal warning when captive_portal_login_required is false' do
          result = subject.status_line(status_data)
          expect(result).not_to match(/Captive Portal/)
        end

        it 'does not show captive portal warning when captive_portal_login_required is :unknown' do
          data = status_data.merge(captive_portal_login_required: :unknown)
          result = subject.status_line(data)
          expect(result).not_to match(/Captive Portal/)
        end

        it 'shows captive portal warning with icon and red color when login_required is :yes' do
          data = status_data.merge(captive_portal_login_required: :yes, internet_state: :unreachable)
          result = subject.status_line(data)

          expect(result).to match(/Captive Portal Login Required/)
          expect(result).to include('⚠️')
          expect(result).to match(red_text_regex)
        end

        it 'shows captive portal warning even when status_data has no captive_portal_login_required key' do
          data = status_data.except(:captive_portal_login_required)
          result = subject.status_line(data)
          expect(result).not_to match(/Captive Portal/)
        end
      end

      it 'shows UNKNOWN when internet status is indeterminate after checks complete' do
        data = status_data.merge(internet_state: :indeterminate, captive_portal_login_required: :unknown)
        result = subject.status_line(data)

        expect(result).to match(/Internet.*UNKNOWN/)
        expect(result).to match(yellow_text_regex)
      end
    end

    context 'when stdout is not a TTY' do
      before { allow(subject.out_stream).to receive(:tty?).and_return(false) }

      it 'contains all status components without color codes' do
        result = subject.status_line(status_data)

        # Test logical content
        expect(result).to match(/WiFi.*ON/)
        expect(result).to match(/WiFi Network.*TestNetwork/)  # network_name is included in test data
        expect(result).to match(/DNS.*YES/)
        expect(result).to match(/Internet.*YES/)

        # Verify no color codes
        expect(result).not_to match(ansi_color_regex)
      end

      it 'appends percent signal quality after a connected network name' do
        data = status_data.merge(
          connected:      true,
          signal_quality: WifiWand::SignalQuality.new(value: 72, unit: :percent)
        )

        result = subject.status_line(data)

        expect(result).to include('TestNetwork (72%)')
      end

      it 'shows error conditions without color codes' do
        data = status_data.clone
        data[:wifi_on] = false
        data[:dns_working] = false
        result = subject.status_line(data)

        expect(result).to match(/WiFi.*OFF/)
        expect(result).to match(/DNS.*NO/)
        expect(result).not_to match(ansi_color_regex)
      end

      it 'shows DNS as WAIT when the check has not completed yet' do
        data = status_data.merge(dns_working: nil, internet_state: :pending, internet_check_complete: false)
        result = subject.status_line(data)

        expect(result).to match(/DNS.*WAIT/)
        expect(result).to match(/Internet.*WAIT/)
        expect(result).not_to match(ansi_color_regex)
      end

      it 'shows fallback status without color codes' do
        result = subject.status_line(nil)

        expect(result).to match(/WiFi.*status unavailable/)
        expect(result).not_to match(ansi_color_regex)
      end

      context 'when captive portal is detected' do
        it 'shows captive portal warning text without ANSI color codes' do
          data = status_data.merge(captive_portal_login_required: :yes, internet_state: :unreachable)
          result = subject.status_line(data)

          expect(result).to match(/Captive Portal Login Required/)
          expect(result).to include('⚠️')
          expect(result).not_to match(ansi_color_regex)
        end

        it 'does not show captive portal warning when not required' do
          result = subject.status_line(status_data)
          expect(result).not_to match(/Captive Portal/)
        end
      end

      it 'shows UNKNOWN without ANSI color codes when internet status is indeterminate' do
        data = status_data.merge(internet_state: :indeterminate, captive_portal_login_required: :unknown)
        result = subject.status_line(data)

        expect(result).to match(/Internet.*UNKNOWN/)
        expect(result).not_to match(ansi_color_regex)
      end
    end
  end

  describe '#post_process' do
    let(:test_object) { { key: 'value' } }

    context 'when post_processor is set' do
      let(:processor) { ->(obj) { obj.to_s.upcase } }
      let(:options) { WifiWand::CommandLineOptions.new(post_processor: processor) }

      it 'applies the post processor' do
        result = subject.post_process(test_object)
        # Accept both old Ruby format and new Ruby format
        expect(result).to eq('{:KEY=>"VALUE"}').or eq('{KEY: "VALUE"}')
      end

      it 'applies display conversion before post processing Time values' do
        utc_options = WifiWand::CommandLineOptions.new(
          post_processor: ->(obj) { JSON.generate(obj) },
          utc:            true
        )
        formatter = test_class.new(utc_options, mock_model)
        timestamp = Time.new(2026, 5, 17, 18, 3, 50, '+07:00')

        result = formatter.post_process({ timestamp: timestamp })

        expect(JSON.parse(result)).to eq('timestamp' => '2026-05-17T11:03:50Z')
        expect(timestamp.utc_offset).to eq(7 * 60 * 60)
      end
    end

    context 'when post_processor is nil' do
      it 'returns display-safe data without post processing' do
        result = subject.post_process(test_object)
        expect(result).to eq(test_object)
      end

      it 'applies display conversion to Time values' do
        timestamp = Time.new(2026, 5, 17, 18, 3, 50, '+07:00')
        utc_options = WifiWand::CommandLineOptions.new(post_processor: nil, utc: true)
        formatter = test_class.new(utc_options, mock_model)

        result = formatter.post_process({ timestamp: timestamp })

        expect(result).to eq(timestamp: '2026-05-17T11:03:50Z')
        expect(timestamp.utc_offset).to eq(7 * 60 * 60)
      end
    end
  end

  describe '#post_processor' do
    context 'when options has post_processor' do
      let(:processor) { ->(x) { x.to_s } }
      let(:options) { WifiWand::CommandLineOptions.new(post_processor: processor) }

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
