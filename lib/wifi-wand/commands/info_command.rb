# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class InfoCommand < Command
    SHORT_NAME = 'i'
    LONG_NAME = 'info'
    DESCRIPTION = 'a hash of detailed networking information'
    USAGE = 'Usage: wifi-wand info'

    binds :cli, :model

    def call
      info = model.wifi_info
      cli.send(:handle_output, info, -> { cli.send(:format_object, info) })
    end
  end
end
