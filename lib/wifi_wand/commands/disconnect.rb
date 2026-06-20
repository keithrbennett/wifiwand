# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Disconnect < Base
      command_metadata(
        short_string: 'd',
        long_string:  'disconnect',
        description:  'disconnect from the current WiFi network without turning WiFi off',
        usage:        'Usage: wifiwand disconnect'
      )

      binds :model
      allow_invocation_options :wifi_interface

      def call(*args)
        validate_max_arguments!(args, 0)

        model.disconnect
      end
    end
  end
end
