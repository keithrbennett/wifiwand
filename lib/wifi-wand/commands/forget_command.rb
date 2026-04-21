# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ForgetCommand < Command
    SHORT_NAME = 'f'
    LONG_NAME = 'forget'
    DESCRIPTION = 'remove one or more preferred (saved) WiFi networks'
    USAGE = 'Usage: wifi-wand forget <name1> [name2 ...]'

    binds :cli, :model

    def call(*options)
      removed_networks = model.remove_preferred_networks(*options)
      cli.send(:handle_output, removed_networks, -> { "Removed networks: #{removed_networks.inspect}" })
    end
  end
end
