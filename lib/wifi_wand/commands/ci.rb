# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Ci < Base
      command_metadata(
        short_string: 'ci',
        long_string:  'ci',
        description:  'Internet connectivity state: reachable, unreachable, or indeterminate',
        usage:        'Usage: wifi-wand ci'
      )

      binds :model, :interactive_mode, output_support: :output_support
      allow_invocation_options :wifi_interface, :output_format

      def call(*args)
        validate_max_arguments!(args, 0)

        state = model.internet_connectivity_state
        output_value = interactive_mode ? state : state.to_s
        output_support.handle_output(output_value, -> { "Internet connectivity: #{state}" })
      end
    end
  end
end
