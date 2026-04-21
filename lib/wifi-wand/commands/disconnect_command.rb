# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class DisconnectCommand < Command
    SHORT_NAME = 'd'
    LONG_NAME = 'disconnect'
    DESCRIPTION = 'disconnect from the current WiFi network without turning WiFi off'
    USAGE = 'Usage: wifi-wand disconnect'

    attr_reader :metadata, :model

    def bind(cli)
      self.class.new(metadata: metadata, model: cli.model)
    end

    def call
      model.disconnect
    end
  end
end
