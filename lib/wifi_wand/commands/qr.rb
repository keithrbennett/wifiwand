# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Qr < Base
      command_metadata(
        short_string: 'qr',
        long_string:  'qr',
        description:  'generate a Wi-Fi QR code',
        usage:        'Usage: wifi-wand qr [filespec] [password]'
      )

      binds :model, :interactive_mode, :in_stream, output_support: :output_support
      allow_invocation_options :wifi_interface, :output_format

      def help_text
        <<~HELP
          #{metadata.usage}

          #{metadata.description}

          Default output prints an ANSI QR to stdout
          Pass a filename to write a QR image file
          Use '-' explicitly for stdout when passing a password
          Use .svg or .eps for those formats
          Optional password avoids the macOS auth prompt
        HELP
      end

      def call(*args)
        validate_max_arguments!(args, 2)

        filespec, password = args

        if stdout_target?(filespec)
          validate_stdout_output_format!
          model.print_qr_code(password: password, in_stream: in_stream)
          interactive_mode ? silent_result : nil
        else
          result = model.generate_qr_code(filespec, password: password, in_stream: in_stream)
          output_support.handle_output(result, -> { "QR code generated: #{result}" })
        end
      end

      def validate_options(invocation_options:, command_options:, args:, context: nil)
        errors = super
        return errors unless stdout_target?(args.first)
        return errors unless Array(invocation_options.specified_invocation_options).include?(:output_format)
        return errors if output_format_source(invocation_options) == :environment

        errors + [stdout_output_format_error]
      end

      private def stdout_target?(filespec)
        spec = filespec&.to_s
        spec.nil? || spec.empty? || spec == '-'
      end

      private def validate_stdout_output_format!
        return unless output_support.respond_to?(:options)
        return unless output_format_specified?(output_support.options)
        return if output_format_source(output_support.options) == :environment

        raise WifiWand::ConfigurationError, stdout_output_format_error
      end

      private def output_format_specified?(invocation_options)
        Array(invocation_options&.specified_invocation_options).include?(:output_format)
      end

      private def output_format_source(invocation_options)
        invocation_options.invocation_option_sources&.fetch(:output_format, nil)
      end

      private def stdout_output_format_error
        '--output-format is not valid for qr stdout output. Pass a filename for formatted file output.'
      end
    end
  end
end
