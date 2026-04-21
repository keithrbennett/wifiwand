# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class OnCommand < Command
    SHORT_NAME = 'on'
    LONG_NAME = 'on'
    DESCRIPTION = 'turn WiFi on'
    USAGE = 'Usage: wifi-wand on'

    attr_reader :metadata, :model

    def bind(cli)
      self.class.new(metadata: metadata, model: cli.model)
    end

    def call
      model.wifi_on
    end
  end
end
