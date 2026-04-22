# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ForgetCommand < Command
    command_metadata(
      short_string: 'f',
      long_string:  'forget',
      description:  'remove one or more preferred (saved) WiFi networks',
      usage:        'Usage: wifi-wand forget <name1> [name2 ...]'
    )

    binds :cli, :model

    def call(*options)
      removed_networks = model.remove_preferred_networks(*options)
      cli.handle_output(removed_networks, -> { "Removed networks: #{removed_networks.inspect}" })
    end
  end
end
