# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OffCommand < Command
    SHORT_NAME = 'of'
    LONG_NAME = 'off'
    DESCRIPTION = 'turn WiFi off'
    USAGE = 'Usage: wifi-wand off'

    attr_reader :metadata, :model

    def bind(cli)
      self.class.new(metadata: metadata, model: cli.model)
    end

    def call
      model.wifi_off
    end
  end
end
