# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OnCommand < Command
    command_metadata(
      short_string: 'on',
      long_string:  'on',
      description:  'turn WiFi on',
      usage:        'Usage: wifi-wand on'
    )

    binds :model

    def call
      model.wifi_on
    end
  end
end
