# frozen_string_literal: true

module WifiWand
  class CommandLineInterface
    class CommandOutputSupport
      attr_reader :cli

      def initialize(cli)
        @cli = cli
      end

      def handle_output(data, human_readable_string_producer)
        if cli.interactive_mode
          data
        else
          output = if cli.options.post_processor
            cli.options.post_processor.(data)
          else
            human_readable_string_producer.call
          end

          cli.out_stream.puts output unless output.to_s.empty?
        end
      end

      def status_progress_mode
        return :none if cli.options.post_processor
        return :none unless cli.out_stream.respond_to?(:tty?) && cli.out_stream.tty?

        :inline
      end

      def strip_ansi(text) = text.to_s.gsub(/\e\[[\d;]*m/, '')

      def available_networks_empty_message
        if cli.model.is_a?(WifiWand::MacOsModel)
          <<~MESSAGE.chomp
            No visible networks were found.
            On macOS 14+, this can mean the helper could not get usable Location Services authorization for WiFi SSIDs.
          MESSAGE
        elsif cli.model.is_a?(WifiWand::UbuntuModel)
          <<~MESSAGE.chomp
            No visible networks were found.
            If you expect to see networks, try running `nmcli device wifi rescan` or check your hardware/drivers.
          MESSAGE
        else
          'No visible networks were found.'
        end
      end

      def format_object(object)
        cli.format_object(object)
      end

      def status_line(data)
        cli.status_line(data)
      end
    end
  end
end
