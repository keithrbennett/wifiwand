# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Off < Base
      command_metadata(
        short_string: 'of',
        long_string:  'off',
        description:  'turn WiFi off',
        usage:        'Usage: wifi-wand off'
      )

      binds :model
      allow_invocation_options :wifi_interface

      def call(*args)
        validate_max_arguments!(args, 0)

        model.wifi_off
      end
    end
  end
end
