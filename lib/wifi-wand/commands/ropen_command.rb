# frozen_string_literal: true

require_relative 'command'
require_relative '../models/helpers/resource_manager'

module WifiWand
  class RopenCommand < Command
    command_metadata(
      short_string: 'ro',
      long_string:  'ropen',
      description:  'open web resources',
      usage:        'Usage: wifi-wand ropen [resource_code ...]'
    )

    binds :model, :interactive_mode, :out_stream, :err_stream

    def help_text
      <<~HELP
        #{super}

        #{resource_manager.available_resources_help}
      HELP
    end

    def call(*resource_codes)
      if resource_codes.empty?
        help = resource_manager.available_resources_help

        if interactive_mode
          help
        else
          out_stream.puts(help)
          nil
        end
      else
        result = resource_manager.open_resources_by_codes(model, *resource_codes)

        unless result[:invalid_codes].empty?
          err_stream.puts(resource_manager.invalid_codes_error(result[:invalid_codes]))
        end

        nil
      end
    end

    private def resource_manager
      @resource_manager ||= WifiWand::Helpers::ResourceManager.new
    end
  end
end
