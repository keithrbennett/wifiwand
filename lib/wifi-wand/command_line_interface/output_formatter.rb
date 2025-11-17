# frozen_string_literal: true

require 'awesome_print'

module WifiWand
  class CommandLineInterface
    module OutputFormatter
      def format_object(object)
        object.awesome_inspect
      end

      def colorize_text(text, color = nil)
        return text unless $stdout.tty? && color

        color_codes = {
          red: "\e[31m",
          green: "\e[32m",
          yellow: "\e[33m",
          blue: "\e[34m",
          cyan: "\e[36m",
          magenta: "\e[35m",
          bold: "\e[1m",
          reset: "\e[0m"
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

      def colorize_network_name(text)
        # Color quoted network names
        text.gsub(/"([^"]*)"/) { |match| colorize_text(match, :cyan) }
      end

      def colorize_values(text)
        # Color numbers, percentages, and IP addresses
        text.gsub(/\b\d+%|\b\d+\.\d+\.\d+\.\d+|\b\d+\b/) { |match| colorize_text(match, :blue) }
      end

      def format_boolean_status(value, true_char: '✅ YES', false_char: '❌ NO',
        pending_char: '⏳ WAIT')
        value = !value.nil? unless value.nil? # convert non-Boolean non-nil values to true or false
        char, color = case value
                      when nil
                        [pending_char, :yellow]
                      when true
                        [true_char, :green]
                      when false
                        [false_char, :red]
        end

        colorize_text(char, color)
      end

      def status_line(status_data)
        return colorize_text('WiFi: [status unavailable]', :yellow) if status_data.nil?

        wifi_status = format_boolean_status(status_data[:wifi_on])
        internet_status = format_boolean_status(status_data[:internet_connected])

        # Only include network field if it was actually fetched
        result = "WiFi: #{wifi_status}"

        if status_data.key?(:network_name)
          network_name = status_data[:network_name]
          network_text, network_color =
            if network_name == :pending
              ['WAIT', :yellow]
            elsif network_name.nil? || network_name.to_s.empty?
              ['[none]', :yellow]
            else
              [network_name.to_s, :cyan]
            end

          network_display = colorize_text(network_text, network_color)
          result += " | Network: #{network_display}"
        end

        result += " | Internet: #{internet_status}"
        result
      end

      # If a post-processor has been configured (e.g. YAML or JSON), use it.
      def post_process(object)
        post_processor ? post_processor.(object) : object
      end

      def post_processor
        options.post_processor
      end
    end
  end
end
