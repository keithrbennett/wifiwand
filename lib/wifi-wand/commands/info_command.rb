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

    binds :cli, :model

    def call
      info = model.wifi_info
      cli.send(:handle_output, info, -> { cli.send(:format_object, info) })
    end
  end
end
