# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class WifiOnCommand < Command
    SHORT_NAME = 'w'
    LONG_NAME = 'wifi_on'
    DESCRIPTION = 'is the WiFi on?'
    USAGE = 'Usage: wifi-wand wifi_on'

    attr_reader :metadata, :cli, :model

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli, model: cli.model)
    end

    def call
      on = model.wifi_on?
      cli.send(:handle_output, on, -> { "Wifi on: #{on}" })
    end
  end
end
