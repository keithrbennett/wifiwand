# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class RopenCommand < Command
    command_metadata(
      short_string: 'ro',
      long_string:  'ropen',
      description:  'open web resources',
      usage:        'Usage: wifi-wand ropen [resource_code ...]'
    )

    binds :cli, :model, :interactive_mode, :out_stream, :err_stream

    def help_text
      base = super

      if model
        "#{base}

#{model.available_resources_help}"
      else
        base
      end
    end

    def call(*resource_codes)
      if resource_codes.empty?
        if interactive_mode
          model.available_resources_help
        else
          out_stream.puts(model.available_resources_help)
          nil
        end
      else
        result = model.open_resources_by_codes(*resource_codes)

        unless result[:invalid_codes].empty?
          err_stream.puts(model.resource_manager.invalid_codes_error(result[:invalid_codes]))
        end

        nil
      end
    end
  end
end
