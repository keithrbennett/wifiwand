# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class PrefNets < Base
      command_metadata(
        short_string: 'pr',
        long_string:  'pref_nets',
        description:  'show the preferred (saved) WiFi networks',
        usage:        'Usage: wifi-wand pref_nets'
      )

      binds :model, output_support: :output_support

      def call(*args)
        validate_max_arguments!(args, 0)

        networks = model.preferred_networks
        output_support.handle_output(networks, -> { output_support.format_object(networks) })
      end
    end
  end
end
