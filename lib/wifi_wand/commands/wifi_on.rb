# frozen_string_literal: true

require_relative 'base'

module WifiWand
  module Commands
    class WifiOn < Base
      command_metadata(
        short_string: 'w',
        long_string:  'wifi_on',
        description:  'is the WiFi on?',
        usage:        'Usage: wifi-wand wifi_on'
      )

      binds :model, output_support: :output_support
      allow_invocation_options :wifi_interface, :output_format

      def call(*args)
        validate_max_arguments!(args, 0)

        on = model.wifi_on?
        output_support.handle_output(on, -> { "Wifi on: #{on}" })
      end
    end
  end
end
