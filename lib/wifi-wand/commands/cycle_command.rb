# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class CycleCommand < Command
    SHORT_NAME = 'cy'
    LONG_NAME = 'cycle'
    DESCRIPTION = 'cycle WiFi off and back on'
    USAGE = 'Usage: wifi-wand cycle'

    attr_reader :metadata, :model

    def bind(cli)
      self.class.new(metadata: metadata, model: cli.model)
    end

    def call
      model.cycle_network
    end
  end
end
