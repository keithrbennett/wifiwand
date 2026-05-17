# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Forget < Base
      command_metadata(
        short_string: 'f',
        long_string:  'forget',
        description:  'remove one or more preferred (saved) WiFi networks',
        usage:        'Usage: wifi-wand forget <name1> [name2 ...]'
      )

      binds :model, output_support: :output_support
      allow_invocation_options :wifi_interface, :output_format

      def call(*options)
        validate_network_names!(options)

        removed_networks = model.remove_preferred_networks(*options)
        output_support.handle_output(removed_networks, -> { "Removed networks: #{removed_networks.inspect}" })
      end

      private def validate_network_names!(options)
        options.each_with_index do |option, index|
          raise_missing_argument!("<name#{index + 1}>") if missing_argument?(option)
        end
        raise_missing_argument!('<name1>') if options.empty?
      end
    end
  end
end
