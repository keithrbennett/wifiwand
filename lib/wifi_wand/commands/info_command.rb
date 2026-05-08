# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class InfoCommand < Command
    command_metadata(
      short_string: 'i',
      long_string:  'info',
      description:  'a hash of detailed networking information',
      usage:        'Usage: wifi-wand info'
    )

    binds :model, output_support: :output_support

    def call
      info = model.wifi_info
      output_support.handle_output(info, -> { output_support.format_object(info) })
    end
  end
end
