# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class Cycle < Base
      command_metadata(
        short_string: 'cy',
        long_string:  'cycle',
        description:  'cycle WiFi off and back on',
        usage:        'Usage: wifiwand cycle'
      )

      binds :model
      allow_invocation_options :wifi_interface

      def call(*args)
        validate_max_arguments!(args, 0)

        model.cycle_network
      end
    end
  end
end
