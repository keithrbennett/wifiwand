# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class CiCommand < Command
    SHORT_NAME = 'ci'
    LONG_NAME = 'ci'
    DESCRIPTION = 'Internet connectivity state: reachable, unreachable, or indeterminate'
    USAGE = 'Usage: wifi-wand ci'

    binds :cli, :model, :interactive_mode

    def call
      state = model.internet_connectivity_state
      output_value = interactive_mode ? state : state.to_s
      cli.send(:handle_output, output_value, -> { "Internet connectivity: #{state}" })
    end
  end
end
