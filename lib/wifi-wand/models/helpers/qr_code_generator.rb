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
# - Requires the `qrencode` tool to be installed and available on PATH.
# - For PDF output, generate SVG first and convert with a separate tool
#   (e.g., rsvg-convert/inkscape, or ImageMagick’s `magick`),
#   as qrencode doesn’t emit PDF.
# - In shell (REPL), when filespec is '-', this returns the ANSI QR string; call `puts` on it to render.

require 'tempfile'

module WifiWand
  module Helpers
    class QrCodeGenerator
      def generate(model, filespec = nil, overwrite: false, delivery_mode: :print, password: nil,
        in_stream: $stdin)
        ensure_qrencode_available(model)

        network_name = require_connected_network_name(model)
        # If no password is provided, ask the model for the current network password.
        password ||= connected_password_for(model)
        security     = model.connection_security_type
        is_hidden    = model.network_hidden?

        # Normalize filespec for robust API (support symbols as '-' too)
        spec = filespec.nil? ? nil : filespec.to_s

        qr_string = build_wifi_qr_string(network_name, password, security, is_hidden)
        return run_qrencode_text(model, qr_string, delivery_mode: delivery_mode) if spec == '-'

        filename  = spec && !spec.empty? ? spec : build_filename(network_name)
        confirm_overwrite(filename, overwrite: overwrite, output_stream: model.out_stream,
          input_stream: in_stream)
        run_qrencode_file(model, filename, qr_string)
        filename
      end

      private def ensure_qrencode_available(model)
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
        raise WifiWand::Error,
          "Required operating system dependency 'qrencode' library not found. " \
            "Use #{install_command} to install it."
      end

      private def require_connected_network_name(model)
        name = model.connected_network_name
        unless name
          raise WifiWand::Error, 'Not connected to any WiFi network. ' \
            'Connect to a network first.'
        end

        name
      end

      private def connected_password_for(model)
        network_name = model.connected_network_name
        return nil unless network_name

        # QR generation may block on a macOS keychain auth dialog, so do not
        # route through BaseModel#connected_network_password's default timeout.
        model.preferred_network_password(network_name, timeout_in_secs: nil)
      end

      private def build_wifi_qr_string(network_name, password, security_type, is_hidden = false)
        qr_password = password.to_s
        qr_security = map_security_for_qr(security_type, !qr_password.empty?)

        escaped_ssid     = escape_field(network_name)
        escaped_password = escape_field(qr_password)
        hidden_flag      = is_hidden ? 'true' : 'false'

        "WIFI:T:#{qr_security};S:#{escaped_ssid};P:#{escaped_password};H:#{hidden_flag};;"
      end

      private def map_security_for_qr(security_type, password_present)
        case security_type
        when 'WPA', 'WPA2', 'WPA3'
          'WPA'
        when 'WEP'
          'WEP'
        else
          password_present ? 'WPA' : 'nopass'
        end
      end

      private def escape_field(value)
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

      private def build_filename(network_name)
        safe = network_name.gsub(/[^\w\-_]/, '_')
        "#{safe}-qr-code.png"
      end

      private def confirm_overwrite(filename, overwrite: false, output_stream: $stdout, input_stream: $stdin)
        return unless File.exist?(filename)
        return if overwrite

        if input_stream.tty?
          output_stream.print 'Output file exists. Overwrite? [y/N]: '
          answer = input_stream.gets&.strip&.downcase
          if %w[y yes].include?(answer)
            nil
          else
            raise WifiWand::Error, 'Overwrite cancelled: file exists'
          end
        else
          # Non-interactive: instruct the user to delete first
          raise WifiWand::Error,
            "QR code output file '#{filename}' already exists. " \
              'Delete the file first or confirm overwrite in the client.'
        end
      end

      private def run_qrencode_file(model, filename, qr_string)
        Tempfile.create(tempfile_args_for(filename), tempfile_directory_for(filename)) do |tempfile|
          staged_filename = tempfile.path
          tempfile.close

          type_flags = qr_type_flag_for(filename)
          cmd = ['qrencode'] + type_flags + ['-o', staged_filename, qr_string]

          begin
            model.run_command_using_args(cmd)
            File.rename(staged_filename, filename)
            model.out_stream.puts "QR code generated: #{filename}" if model.verbose_mode
          rescue WifiWand::CommandExecutor::OsCommandError => e
            raise WifiWand::Error, "Failed to generate QR code: #{e.message}"
          rescue SystemCallError => e
            raise WifiWand::Error,
              "Failed to replace QR code output file '#{filename}': #{e.message}"
          end
        end
      end

      private def run_qrencode_text(model, qr_string, delivery_mode: :print)
        cmd = %w[qrencode -t ANSI] + [qr_string]
        begin
          result = model.run_command_using_args(cmd)
          output = result.stdout
          if delivery_mode.to_sym == :return
            output
          else
            model.out_stream.print(output)
            '-'
          end
        rescue WifiWand::CommandExecutor::OsCommandError => e
          raise WifiWand::Error, "Failed to generate QR code: #{e.message}"
        end
      end

      private def qr_type_flag_for(filename)
        case File.extname(filename).downcase
        when '.svg' then %w[-t SVG]
        when '.eps' then %w[-t EPS]
        else [] # default PNG (no type flag needed)
        end
      end

      private def tempfile_args_for(filename)
        basename = File.basename(filename, File.extname(filename))
        extension = File.extname(filename)
        ["#{basename}-", extension]
      end

      private def tempfile_directory_for(filename)
        directory = File.dirname(filename)
        directory.empty? ? '.' : directory
      end
    end
  end
end
