require 'shellwords'

module WifiWand
  module Helpers
    class QrCodeGenerator
      def generate(model, filespec = nil)
        ensure_qrencode_available!(model)

        network_name = require_connected_network_name(model)
        password     = connected_password_for(model)
        security     = model.connection_security_type

        qr_string = build_wifi_qr_string(network_name, password, security)
        return run_qrencode_text!(model, qr_string) if filespec == '-'

        filename  = filespec && !filespec.empty? ? filespec : build_filename(network_name)
        confirm_overwrite!(filename)
        run_qrencode_file!(model, filename, qr_string)
        filename
      end

      private

      def ensure_qrencode_available!(model)
        available = model.send(:command_available_using_which?, 'qrencode')
        return if available

        install_command = case WifiWand::OperatingSystems.current_os&.id
                          when :mac
                            'brew install qrencode'
                          when :ubuntu
                            'sudo apt install qrencode'
                          else
                            'install qrencode using your system package manager'
                          end
        raise WifiWand::Error.new("Required operating system dependency 'qrencode' library not found. Use #{install_command} to install it.")
      end

      def require_connected_network_name(model)
        name = model.connected_network_name
        raise WifiWand::Error.new('Not connected to any WiFi network. Connect to a network first.') unless name
        name
      end

      def connected_password_for(model)
        # Use the model's private helper to preserve behavior
        model.send(:connected_network_password)
      end

      def build_wifi_qr_string(network_name, password, security_type)
        qr_security = map_security_for_qr(security_type)
        qr_password = password || ''

        escaped_ssid     = escape_field(network_name)
        escaped_password = escape_field(qr_password)

        "WIFI:T:#{qr_security};S:#{escaped_ssid};P:#{escaped_password};H:false;;"
      end

      def map_security_for_qr(security_type)
        case security_type
        when 'WPA', 'WPA2', 'WPA3'
          'WPA'
        when 'WEP'
          'WEP'
        else
          '' # Open network
        end
      end

      def escape_field(value)
        value.to_s.gsub(/[;,:\\]/) { |char| "\\#{char}" }
      end

      def build_filename(network_name)
        safe = network_name.gsub(/[^\w\-_]/, '_')
        "#{safe}-qr-code.png"
      end

      def confirm_overwrite!(filename)
        return unless File.exist?(filename)

        if $stdin.tty?
          print "File '#{filename}' already exists. Overwrite? [y/N]: "
          answer = $stdin.gets&.strip&.downcase
          unless %w[y yes].include?(answer)
            raise WifiWand::Error.new('QR code generation cancelled: file exists and overwrite not confirmed')
          end
        else
          raise WifiWand::Error.new("QR code output file '#{filename}' already exists. Delete the file first or run interactively to confirm overwrite.")
        end
      end

      def run_qrencode_file!(model, filename, qr_string)
        cmd = "qrencode -o #{Shellwords.shellescape(filename)} #{Shellwords.shellescape(qr_string)}"
        begin
          model.run_os_command(cmd)
          puts "QR code generated: #{filename}" if model.verbose_mode
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end

      def run_qrencode_text!(model, qr_string)
        cmd = "qrencode -t ANSI #{Shellwords.shellescape(qr_string)}"
        begin
          output = model.run_os_command(cmd)
          print output
          '-'
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end
    end
  end
end
