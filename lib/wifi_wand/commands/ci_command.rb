# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class CiCommand < Command
    command_metadata(
      short_string: 'ci',
      long_string:  'ci',
      description:  'Internet connectivity state: reachable, unreachable, or indeterminate',
      usage:        'Usage: wifi-wand ci'
    )

    binds :model, :interactive_mode, output_support: :output_support

    def call
      state = model.internet_connectivity_state
      output_value = interactive_mode ? state : state.to_s
      output_support.handle_output(output_value, -> { "Internet connectivity: #{state}" })
    end
  end
end
