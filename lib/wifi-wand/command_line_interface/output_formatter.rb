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
        when /true|on|connected|yes/
          colorize_text(text, :green)
        when /false|off|disconnected|no/
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

      def status_line
        
        begin
          wifi_on = model.wifi_on?
          wifi_status = wifi_on ? colorize_text("ON", :green) : colorize_text("OFF", :red)
          
          network_name = model.connected_network_name
          network_display = network_name ? colorize_text("\"#{network_name}\"", :cyan) : colorize_text("[none]", :yellow)

          # Test connectivity components
          tcp_working = model.internet_tcp_connectivity?
          tcp_status = tcp_working ? colorize_text("YES", :green) : colorize_text("NO", :red)

          dns_working = model.dns_working?
          dns_status = dns_working ? colorize_text("YES", :green) : colorize_text("NO", :red)

          internet_connected = model.connected_to_internet?
          internet_status = internet_connected ? colorize_text("YES", :green) : colorize_text("NO", :red)

          "WiFi: #{wifi_status} | Network: #{network_display} | TCP: #{tcp_status} | DNS: #{dns_status} | Internet: #{internet_status}"
        rescue => e
          # Fallback if any status check fails
          colorize_text("WiFi: [status unavailable]", :yellow)
        end
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