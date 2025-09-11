# QrCodeGenerator
# ----------------
# Generates Wi‑Fi QR codes for the currently connected network.
#
# Capabilities
# - File output: writes a QR image to a file. By default uses PNG. When the
#   filespec ends with .svg or .eps, output type is set accordingly.
# - Stdout output: when filespec is '-' prints an ANSI QR to stdout.
# - Overwrite safety: prompts before overwriting existing files in interactive
#   TTY sessions; errors in non‑interactive mode if the file exists.
#
# Usage (through BaseModel#generate_qr_code):
#   model.generate_qr_code                # ./<SSID>-qr-code.png (PNG)
#   model.generate_qr_code('wifi.svg')    # ./wifi.svg (SVG)
#   model.generate_qr_code('wifi.eps')    # ./wifi.eps (EPS)
#   model.generate_qr_code('-')           # prints ANSI QR to stdout
#
# Notes
# - Requires the 'qrencode' tool to be installed and available on PATH.
# - For PDF output, generate SVG first and convert with a separate tool
#   (e.g., rsvg-convert/inkscape, or ImageMagick’s `magick`),
#   as qrencode doesn’t emit PDF.

require 'shellwords'

module WifiWand
  module Helpers
    class QrCodeGenerator
      def generate(model, filespec = nil, overwrite: false)
        ensure_qrencode_available!(model)

        network_name = require_connected_network_name(model)
        password     = connected_password_for(model)
        security     = model.connection_security_type

        qr_string = build_wifi_qr_string(network_name, password, security)
        return run_qrencode_text!(model, qr_string) if filespec == '-'

        filename  = filespec && !filespec.empty? ? filespec : build_filename(network_name)
        confirm_overwrite!(filename, overwrite: overwrite)
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
        # Prefix a single backslash before ; , : and double for backslash itself
        value.to_s.gsub(/[;,:\\]/) do |char|
          case char
          when ';' then '\\;'
          when ',' then '\\,'
          when ':' then '\\:'
          when '\\' then '\\\\'
          end
        end
      end

      def build_filename(network_name)
        safe = network_name.gsub(/[^\w\-_]/, '_')
        "#{safe}-qr-code.png"
      end

      def confirm_overwrite!(filename, overwrite: false)
        return unless File.exist?(filename)

        if overwrite
          begin
            File.delete(filename)
          rescue
            raise WifiWand::Error.new("QR code output file '#{filename}' already exists and could not be overwritten.")
          end
          return
        end

        if $stdin.tty?
          $stdout.print "Output file exists. Overwrite? [y/N]: "
          answer = $stdin.gets&.strip&.downcase
          if %w[y yes].include?(answer)
            begin
              File.delete(filename)
            rescue
              raise WifiWand::Error.new("QR code output file '#{filename}' already exists and could not be overwritten.")
            end
            return
          else
            raise WifiWand::Error.new('Overwrite cancelled: file exists')
          end
        else
          # Non-interactive: instruct the user to delete first
          raise WifiWand::Error.new("QR code output file '#{filename}' already exists. Delete the file first or confirm overwrite in the client.")
        end
      end

      def run_qrencode_file!(model, filename, qr_string)
        type_flag = qr_type_flag_for(filename)
        cmd = [
          'qrencode',
          type_flag,
          '-o', Shellwords.shellescape(filename),
          Shellwords.shellescape(qr_string)
        ].compact.join(' ')
        begin
          model.run_os_command(cmd)
          model.out_stream.puts "QR code generated: #{filename}" if model.verbose_mode
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end

      def run_qrencode_text!(model, qr_string)
        cmd = "qrencode -t ANSI #{Shellwords.shellescape(qr_string)}"
        begin
          output = model.run_os_command(cmd)
          # Print ANSI QR directly to stdout for compatibility with tests/CLI
          $stdout.print(output)
          '-'
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end

      def qr_type_flag_for(filename)
        case File.extname(filename).downcase
        when '.svg' then '-t SVG'
        when '.eps' then '-t EPS'
        else nil # default PNG
        end
      end
    end
  end
end
