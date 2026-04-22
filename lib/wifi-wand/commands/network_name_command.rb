# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class NetworkNameCommand < Command
    command_metadata(
      short_string: 'ne',
      long_string:  'network_name',
      description:  'show the SSID of the currently connected WiFi network',
      usage:        'Usage: wifi-wand network_name'
    )

    binds :cli, :model

    def call
      name = model.connected_network_name
      cli.send(:handle_output, name, -> { %{Network (SSID) name: "#{name || '[none]'}"} })
    rescue WifiWand::Error => e
      cli.send(:handle_output, nil, -> { e.message })
    end
  end
end
