# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class CycleCommand < Command
    command_metadata(
      short_string: 'cy',
      long_string:  'cycle',
      description:  'cycle WiFi off and back on',
      usage:        'Usage: wifi-wand cycle'
    )

    binds :model

    def call
      model.cycle_network
    end
  end
end
