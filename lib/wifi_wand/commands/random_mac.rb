# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class RandomMac < Base
      command_metadata(
        short_string: 'rmac',
        long_string:  'random_mac',
        description:  'generate a random locally administered unicast MAC address',
        usage:        'Usage: wifi-wand random_mac'
      )

      binds :model, output_support: :output_support
      allow_invocation_options :output_format

      def call(*args)
        validate_max_arguments!(args, 0)

        mac_address = model.random_mac_address
        output_support.handle_output(mac_address, -> { mac_address })
      end
    end
  end
end
