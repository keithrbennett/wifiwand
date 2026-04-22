# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class AvailNetsCommand < Command
    command_metadata(
      short_string: 'a',
      long_string:  'avail_nets',
      description:  'list visible WiFi networks in descending signal-strength order',
      usage:        'Usage: wifi-wand avail_nets'
    )

    binds :cli, :model

    def call
      info = model.available_network_names
      cli.send(:handle_output, info, human_readable_string_producer(info))
    rescue WifiWand::Error => e
      cli.send(:handle_output, nil, -> { e.message })
    end

    private def human_readable_string_producer(info)
      -> do
        if info.respond_to?(:empty?) && info.empty?
          cli.send(:empty_available_networks_message)
        else
          <<~MESSAGE
            Available networks, in descending signal strength order,
            as returned by the OS scan, are:

            #{cli.send(:format_object, info)}
          MESSAGE
        end
      end
    end
  end
end
