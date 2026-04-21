# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class QrCommand
    SHORT_NAME = 'qr'
    LONG_NAME = 'qr'
    DESCRIPTION = 'generate a Wi-Fi QR code'
    USAGE = "Usage: wifi-wand qr [filespec|'-'] [password]"

    attr_reader :metadata, :cli, :model, :interactive_mode, :out_stream, :in_stream

    def initialize(metadata: nil, cli: nil, model: nil, interactive_mode: nil, out_stream: nil,
      in_stream: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @model = model
      @interactive_mode = interactive_mode
      @out_stream = out_stream
      @in_stream = in_stream
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(
        metadata:         metadata,
        cli:              cli,
        model:            cli.model,
        interactive_mode: cli.interactive_mode,
        out_stream:       cli.out_stream,
        in_stream:        cli.in_stream
      )
    end

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
        cli.send(:handle_output, result, -> { "QR code generated: #{result}" })
      end
    rescue WifiWand::Error => e
      if e.message.include?('already exists') && in_stream.tty?
        out_stream.print 'Output file exists. Overwrite? [y/N]: '
        answer = in_stream.gets&.strip&.downcase
        if %w[y yes].include?(answer)
          result = model.generate_qr_code(filespec, overwrite: true, password: password)
          cli.send(:handle_output, result, -> { "QR code generated: #{result}" })
        end
      else
        raise
      end
    end
  end
end
