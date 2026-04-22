# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class QrCommand < Command
    command_metadata(
      short_string: 'qr',
      long_string:  'qr',
      description:  'generate a Wi-Fi QR code',
      usage:        "Usage: wifi-wand qr [filespec|'-'] [password]"
    )

    binds :model, :interactive_mode, :out_stream, :in_stream, output_support: :output_support

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}

        Default PNG file: <SSID>-qr-code.png
        Use '-' to print ANSI QR to stdout
        Use .svg or .eps for those formats
        Optional password avoids the macOS auth prompt
      HELP
    end

    def call(filespec = nil, password = nil)
      spec = filespec&.to_s
      to_stdout = (spec == '-')

      if to_stdout
        result = model.generate_qr_code('-', delivery_mode: (interactive_mode ? :return : :print),
          password: password)
        interactive_mode ? result : nil
      else
        result = model.generate_qr_code(filespec, password: password)
        output_support.handle_output(result, -> { "QR code generated: #{result}" })
      end
    rescue WifiWand::Error => e
      if e.message.include?('already exists') && in_stream.tty?
        out_stream.print 'Output file exists. Overwrite? [y/N]: '
        answer = in_stream.gets&.strip&.downcase
        if %w[y yes].include?(answer)
          result = model.generate_qr_code(filespec, overwrite: true, password: password)
          output_support.handle_output(result, -> { "QR code generated: #{result}" })
        end
      else
        raise
      end
    end
  end
end
