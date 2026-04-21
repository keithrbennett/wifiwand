# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OffCommand < Command
    SHORT_NAME = 'of'
    LONG_NAME = 'off'
    DESCRIPTION = 'turn WiFi off'
    USAGE = 'Usage: wifi-wand off'

    binds :model

    def call
      model.wifi_off
    end
  end
end
