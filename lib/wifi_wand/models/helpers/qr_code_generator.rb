# frozen_string_literal: true

# QrCodeGenerator
# ----------------
# Generates Wi‑Fi QR codes for the currently connected network.
#
# Capabilities
# - File output: writes a QR image to a file. By default uses PNG. File
#   extensions .png, .svg, and .eps are supported.
# - Render output: returns QR data without writing or printing.
# - Overwrite safety: prompts before overwriting existing files in interactive
#   TTY sessions; errors in non‑interactive mode if the file exists.
#
# Usage (through BaseModel#generate_qr_code):
#   model.generate_qr_code                # ./<SSID>-qr-code.png (PNG)
#   model.generate_qr_code('wifi.svg')    # ./wifi.svg (SVG)
#   model.generate_qr_code('wifi.eps')    # ./wifi.eps (EPS)
#   model.render_qr_code(format: :ansi)   # returns ANSI QR string
#   model.render_qr_code(format: :png)    # returns PNG bytes
#   model.print_qr_code                   # prints ANSI QR to stdout
#
# Notes
# - Requires the `qrencode` tool to be installed and available on PATH.
# - For PDF output, generate SVG first and convert with a separate tool
#   (e.g., rsvg-convert/inkscape, or ImageMagick’s `magick`),
#   as qrencode doesn’t emit PDF.
# - In shell (REPL), the `qr` command prints an ANSI QR directly.

require 'tempfile'

require_relative '../../string_predicates'

module WifiWand
  module Helpers
    class QrCodeGenerator
      include StringPredicates

      QR_FIELD_ESCAPES = {
        ';'  => '\\;',
        ','  => '\\,',
        ':'  => '\\:',
        '\\' => '\\\\',
      }.freeze

      RENDER_FORMATS = {
        ansi: 'ANSI',
        png:  'PNG',
        svg:  'SVG',
        eps:  'EPS',
      }.freeze
      BINARY_RENDER_FORMATS = [:png].freeze
      FILE_OUTPUT_FORMATS = {
        '.png' => :png,
        '.svg' => :svg,
        '.eps' => :eps,
      }.freeze

      def generate(model, filespec = nil, overwrite: false, password: nil, in_stream: $stdin)
        # Normalize filespec for robust API.
        spec = filespec&.to_s
        if spec == '-'
          raise WifiWand::Error,
            'Use print_qr_code to print an ANSI QR code or render_qr_code(format: :ansi) to return one.'
        end

        filename = nil
        format = nil
        if spec && !spec.empty?
          filename = spec
          format = qr_output_format_for(filename)
          validate_qr_output_directory_ready!(filename)
        end

        ensure_qrencode_available(model)

        network_name, security, resolved_password, is_hidden = qr_context(model, password)
        qr_string = build_wifi_qr_string(network_name, resolved_password, security, is_hidden: is_hidden)

        filename ||= build_filename(network_name)
        format ||= qr_output_format_for(filename)
        validate_qr_output_directory_ready!(filename) unless spec && !spec.empty?
        confirm_overwrite(filename, overwrite: overwrite, output_stream: model.out_stream,
          input_stream: in_stream)
        rendered_output = render_qr_data(model, qr_string, format: format)
        write_qr_file(model, filename, rendered_output)
        filename
      end

      def render(model, format: :ansi, password: nil)
        qrencode_type = qrencode_type_for(format)
        ensure_qrencode_available(model)

        network_name, security, resolved_password, is_hidden = qr_context(model, password)
        qr_string = build_wifi_qr_string(network_name, resolved_password, security, is_hidden: is_hidden)
        render_qr_data(model, qr_string, format: format, qrencode_type: qrencode_type)
      end

      private def ensure_qrencode_available(model)
        available = model.command_available?('qrencode')
        return if available

        install_command = case WifiWand::Platforms::Selector.current_os&.id
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

      private def qr_context(model, password)
        network_name = require_connected_network_name(model)
        security     = model.connection_security_type
        password     = resolved_password_for(model, network_name, security, password)
        is_hidden    = model.network_hidden?

        [network_name, security, password, is_hidden]
      end

      private def resolved_password_for(model, network_name, security_type, explicit_password)
        if open_security_type?(security_type)
          nil
        elsif blank_password?(explicit_password)
          connected_password_for(model, network_name, security_type)
        else
          explicit_password
        end
      end

      private def connected_password_for(model, network_name, security_type)
        password = model.preferred_network_password(network_name)
        validate_password_available!(network_name, password, security_type)
        password
      rescue WifiWand::PreferredNetworkNotFoundError
        raise missing_password_error(network_name, security_type)
      end

      private def validate_password_available!(network_name, password, security_type)
        if blank_password?(password)
          raise missing_password_error(network_name, security_type)
        end
      end

      private def blank_password?(password)
        string_nil_or_empty?(password)
      end

      private def missing_password_error(network_name, security_type)
        if secured_security_type?(security_type)
          WifiWand::QrCodePasswordUnavailableError.new(
            network_name:  network_name,
            security_type: security_type
          )
        else
          WifiWand::QrCodeSecurityUndeterminedError.new(network_name)
        end
      end

      private def secured_security_type?(security_type)
        %w[WPA WPA2 WPA3 WEP].include?(security_type.to_s.upcase)
      end

      private def open_security_type?(security_type)
        %w[NONE OPEN NOPASS].include?(security_type.to_s.upcase)
      end

      private def build_wifi_qr_string(network_name, password, security_type, is_hidden: false)
        qr_password = password.to_s
        qr_security = map_security_for_qr(security_type)

        escaped_ssid     = escape_field(network_name)
        escaped_password = escape_field(qr_password)
        hidden_flag      = is_hidden ? 'true' : 'false'

        "WIFI:T:#{qr_security};S:#{escaped_ssid};P:#{escaped_password};H:#{hidden_flag};;"
      end

      private def map_security_for_qr(security_type)
        case security_type.to_s.upcase
        when 'WEP'
          'WEP'
        when 'NONE', 'OPEN', 'NOPASS'
          'nopass'
        else
          # QR format uses WPA for WPA/WPA2/WPA3. Unknown secured networks could be WEP,
          # but WPA is the safer default for modern networks.
          'WPA'
        end
      end

      private def escape_field(value)
        # Prefix a single backslash before ; , : and double for backslash itself
        value.to_s.gsub(/[;,:\\]/) do |char|
          QR_FIELD_ESCAPES.fetch(char)
        end
      end

      private def build_filename(network_name)
        safe = network_name.gsub(/[^\w\-_]/, '_')
        "#{safe}-qr-code.png"
      end

      private def confirm_overwrite(filename, overwrite:, output_stream:, input_stream:)
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

      private def write_qr_file(model, filename, rendered_output)
        tempfile = nil
        temp_path = nil

        begin
          tempfile = Tempfile.create(tempfile_args_for(filename), tempfile_directory_for(filename))
          temp_path = tempfile.path
          tempfile.binmode
          tempfile.write(rendered_output)
          tempfile.close

          File.rename(temp_path, filename)
          temp_path = nil
        rescue SystemCallError => e
          raise WifiWand::QrCodeOutputFileError.new(
            filename:  filename,
            directory: tempfile_directory_for(filename),
            reason:    e.message,
            source:    e
          )
        ensure
          delete_tempfile_path(tempfile, temp_path)
        end

        model.err_stream.puts "QR code generated: #{filename}" if model.verbose?
      end

      private def render_qr_data(model, qr_string, format:, qrencode_type: qrencode_type_for(format))
        cmd = ['qrencode', '-t', qrencode_type, '-o', '-', qr_string]

        qrencode_result = model.run_command(
          cmd,
          log_stdout:    false,
          binary_stdout: binary_render_format?(format)
        )
        qrencode_result.stdout
      rescue WifiWand::CommandExecutor::OsCommandError => e
        raise WifiWand::QrCodeGenerationError.new(reason: e.message, source: e)
      end

      private def delete_tempfile_path(tempfile, temp_path)
        return unless tempfile && temp_path && File.exist?(temp_path)

        tempfile.close unless tempfile.closed?
        File.delete(temp_path)
      rescue SystemCallError
        nil
      end

      private def binary_render_format?(format)
        BINARY_RENDER_FORMATS.include?(format.to_sym)
      end

      private def qrencode_type_for(format)
        key = format.to_sym
        RENDER_FORMATS.fetch(key)
      rescue KeyError
        raise ArgumentError, "unsupported QR render format: #{format.inspect}"
      end

      private def qr_output_format_for(filename)
        extension = File.extname(filename).downcase
        return :png if extension.empty?

        FILE_OUTPUT_FORMATS.fetch(extension)
      rescue KeyError
        raise ArgumentError,
          "unsupported QR output file extension: #{extension.inspect}. Use .png, .svg, or .eps."
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

      private def validate_qr_output_directory_ready!(filename)
        directory = tempfile_directory_for(filename)
        return if File.directory?(directory) && File.writable?(directory)

        raise WifiWand::QrCodeOutputFileError.new(filename: filename, directory: directory)
      end
    end
  end
end
