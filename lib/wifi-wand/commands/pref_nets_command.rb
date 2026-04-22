# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PrefNetsCommand < Command
    command_metadata(
      short_string: 'pr',
      long_string:  'pref_nets',
      description:  'show the preferred (saved) WiFi networks',
      usage:        'Usage: wifi-wand pref_nets'
    )

    binds :model, output_support: :output_support

    def call
      networks = model.preferred_networks
      output_support.handle_output(networks, -> { output_support.format_object(networks) })
    end
  end
end
