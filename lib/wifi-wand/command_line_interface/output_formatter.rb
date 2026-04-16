# frozen_string_literal: true

require 'awesome_print'
require_relative '../connectivity_states'

module WifiWand
  class CommandLineInterface
    module OutputFormatter
      def format_object(object) = object.awesome_inspect

      def colorize_text(text, color = nil)
        return text unless out_stream.respond_to?(:tty?) && out_stream.tty? && color

        color_codes = {
          red:     "\e[31m",
          green:   "\e[32m",
          yellow:  "\e[33m",
          blue:    "\e[34m",
          cyan:    "\e[36m",
          magenta: "\e[35m",
          bold:    "\e[1m",
          reset:   "\e[0m",
        }

        "#{color_codes[color]}#{text}#{color_codes[:reset]}"
      end

      def colorize_status(text)
        case text.to_s.downcase
        when /\b(true|on|connected|yes)\b/
          colorize_text(text, :green)
        when /\b(false|off|disconnected|no)\b/
          colorize_text(text, :red)
        else
          text
        end
      end

      def colorize_network_name(text) = text.gsub(/"([^"]*)"/) { |match| colorize_text(match, :cyan) }

      def colorize_values(text)
        text.gsub(/\b\d+%|\b\d+\.\d+\.\d+\.\d+|\b\d+\b/) { |match| colorize_text(match, :blue) }
      end

      def format_boolean_status(value, true_str: '✅ YES', false_str: '❌ NO', pending_str: '⏳ WAIT')
        value = !!value unless value.nil? # convert non-Boolean non-nil values to true or false
        status_text, color = case value
                             when nil
                               [pending_str, :yellow]
                             when true
                               [true_str, :green]
                             when false
                               [false_str, :red]
        end

        colorize_text(status_text, color)
      end

      def format_internet_status(state, check_complete: false)
        status_text, color = case state
                             when ConnectivityStates::INTERNET_REACHABLE
                               ['✅ YES', :green]
                             when ConnectivityStates::INTERNET_UNREACHABLE
                               ['❌ NO', :red]
                             when ConnectivityStates::INTERNET_PENDING
                               ['⏳ WAIT', :yellow]
                             else
                               [check_complete ? '⚠️ UNKNOWN' : '⏳ WAIT', :yellow]
        end

        colorize_text(status_text, color)
      end

      def status_line(status_data)
        return colorize_text('WiFi: [status unavailable]', :yellow) if status_data.nil?

        wifi_status = format_boolean_status(status_data[:wifi_on], true_str: '✅ ON', false_str: '❌ OFF')
        dns_status = format_boolean_status(status_data[:dns_working])
        internet_status = format_internet_status(
          status_data[:internet_state],
          check_complete: status_data[:internet_check_complete]
        )

        # Format network name
        network_name = status_data[:network_name]
        network_text, network_color =
          if network_name == :pending
            ['WAIT', :yellow]
          elsif status_data[:connected] == true && (network_name.nil? || network_name.to_s.empty?)
            ['[SSID unavailable]', :yellow]
          elsif network_name.nil? || network_name.to_s.empty?
            ['[none]', :yellow]
          else
            [network_name.to_s, :cyan]
          end

        wifi_network_status = colorize_text(network_text, network_color)

        line = "WiFi: #{wifi_status} | WiFi Network: #{wifi_network_status} | " \
          "DNS: #{dns_status} | Internet: #{internet_status}"

        if status_data[:captive_portal_login_required] == :yes
          line = "#{line} | #{colorize_text('⚠️ Captive Portal Login Required', :red)}"
        end

        line
      end

      # If a post-processor has been configured (e.g. YAML or JSON), use it.
      def post_process(object) = post_processor ? post_processor.(object) : object

      def post_processor = options.post_processor
    end
  end
end
