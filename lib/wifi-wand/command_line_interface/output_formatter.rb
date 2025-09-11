# frozen_string_literal: true

require 'awesome_print'

module WifiWand
  class CommandLineInterface
    module OutputFormatter
      
      def format_object(object)
        $stdout.tty? ? object.awesome_inspect : object.awesome_inspect(plain: true)
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

      def format_boolean_status(value, true_char: "✅ YES", false_char: "❌ NO")
        char = value ? true_char : false_char
        color = value ? :green : :red
        colorize_text(char, color)
      end

      def status_line(status_data)
        return colorize_text("WiFi: [status unavailable]", :yellow) if status_data.nil?

        wifi_status = format_boolean_status(status_data[:wifi_on])
        
        network_display = if status_data[:network_name]
                            colorize_text("#{status_data[:network_name]}", :cyan)
                          else
                            colorize_text("[none]", :yellow)
                          end

        tcp_status = format_boolean_status(status_data[:tcp_working])
        dns_status = format_boolean_status(status_data[:dns_working])
        internet_status = format_boolean_status(status_data[:internet_connected])

        "WiFi: #{wifi_status} | Network: #{network_display} | TCP: #{tcp_status} | DNS: #{dns_status} | Internet: #{internet_status}"
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