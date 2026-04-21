# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PrefNetsCommand < Command
    SHORT_NAME = 'pr'
    LONG_NAME = 'pref_nets'
    DESCRIPTION = 'show the preferred (saved) WiFi networks'
    USAGE = 'Usage: wifi-wand pref_nets'

    binds :cli, :model

    def call
      networks = model.preferred_networks
      cli.send(:handle_output, networks, -> { cli.send(:format_object, networks) })
    end
  end
end
