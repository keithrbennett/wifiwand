# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OffCommand < Command
    command_metadata(
      short_string: 'of',
      long_string:  'off',
      description:  'turn WiFi off',
      usage:        'Usage: wifi-wand off'
    )

    binds :model

    def call(*args)
      validate_max_arguments!(args, 0)

      model.wifi_off
    end
  end
end
