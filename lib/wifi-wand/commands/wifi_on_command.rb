# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class WifiOnCommand < Command
    command_metadata(
      short_string: 'w',
      long_string:  'wifi_on',
      description:  'is the WiFi on?',
      usage:        'Usage: wifi-wand wifi_on'
    )

    binds :cli, :model

    def call
      on = model.wifi_on?
      cli.send(:handle_output, on, -> { "Wifi on: #{on}" })
    end
  end
end
