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

    binds :model, output_support: :output_support

    def call
      on = model.wifi_on?
      output_support.handle_output(on, -> { "Wifi on: #{on}" })
    end
  end
end
