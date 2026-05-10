# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class DisconnectCommand < Command
    command_metadata(
      short_string: 'd',
      long_string:  'disconnect',
      description:  'disconnect from the current WiFi network without turning WiFi off',
      usage:        'Usage: wifi-wand disconnect'
    )

    binds :model

    def call(*args)
      validate_max_arguments!(args, 0)

      model.disconnect
    end
  end
end
