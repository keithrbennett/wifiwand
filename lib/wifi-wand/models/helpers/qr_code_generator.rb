# frozen_string_literal: true

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
# - Requires the 'Add command_line_interface_spec.rb test coverage.qrencode' tool to be installed and available on PATH.
# - For PDF output, generate SVG first and convert with a separate tool
#   (e.g., rsvg-convert/inkscape, or ImageMagick’s `magick`),
#   as qrencode doesn’t emit PDF.
# - In shell (REPL), when filespec is '-', this returns the ANSI QR string; call `puts` on it to render.

module WifiWand
  module Helpers
    class QrCodeGenerator
      def generate(model, filespec = nil, overwrite: false, delivery_mode: :print, password: nil)
        ensure_qrencode_available(model)

        network_name = require_connected_network_name(model)
        # If no password is provided, fetch the saved password from the system (may require auth on macOS)
        password     = password || connected_password_for(model)
        security     = model.connection_security_type

        # Normalize filespec for robust API (support symbols as '-' too)
        spec = filespec.nil? ? nil : filespec.to_s

        qr_string = build_wifi_qr_string(network_name, password, security)
        return run_qrencode_text(model, qr_string, delivery_mode: delivery_mode) if spec == '-'

        filename  = spec && !spec.empty? ? spec : build_filename(network_name)
        confirm_overwrite(filename, overwrite: overwrite, output_stream: model.out_stream)
        run_qrencode_file(model, filename, qr_string)
        filename
      end

      private

      def ensure_qrencode_available(model)
        available = model.send(:command_available?, 'qrencode')
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
        qr_password = password.to_s
        qr_security = map_security_for_qr(security_type, !qr_password.empty?)

        escaped_ssid     = escape_field(network_name)
        escaped_password = escape_field(qr_password)

        "WIFI:T:#{qr_security};S:#{escaped_ssid};P:#{escaped_password};H:false;;"
      end

      def map_security_for_qr(security_type, password_present)
        case security_type
        when 'WPA', 'WPA2', 'WPA3'
          'WPA'
        when 'WEP'
          'WEP'
        else
          password_present ? 'WPA' : 'nopass'
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

      def confirm_overwrite(filename, overwrite: false, output_stream: $stdout)
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
          output_stream.print "Output file exists. Overwrite? [y/N]: "
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

      def run_qrencode_file(model, filename, qr_string)
        type_flags = qr_type_flag_for(filename)
        cmd = ['qrencode'] + type_flags + ['-o', filename, qr_string]
        begin
          model.run_os_command(cmd)
          model.out_stream.puts "QR code generated: #{filename}" if model.verbose_mode
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end

      def run_qrencode_text(model, qr_string, delivery_mode: :print)
        cmd = %w[qrencode -t ANSI] + [qr_string]
        begin
          result = model.run_os_command(cmd)
          output = result.stdout
          if delivery_mode.to_sym == :return
            output
          else
            # Print ANSI QR directly to stdout for compatibility with tests/CLI
            $stdout.print(output)
            '-'
          end
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error.new("Failed to generate QR code: #{e.message}")
        end
      end

      def qr_type_flag_for(filename)
        case File.extname(filename).downcase
        when '.svg' then %w[-t SVG]
        when '.eps' then %w[-t EPS]
        else [] # default PNG (no type flag needed)
        end
      end
    end
  end
end
