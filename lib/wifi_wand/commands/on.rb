# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class On < Base
      command_metadata(
        short_string: 'on',
        long_string:  'on',
        description:  'turn WiFi on',
        usage:        'Usage: wifi-wand on'
      )

      binds :model
      allow_invocation_options :wifi_interface

      def call(*args)
        validate_max_arguments!(args, 0)

        model.wifi_on
      end
    end
  end
end
