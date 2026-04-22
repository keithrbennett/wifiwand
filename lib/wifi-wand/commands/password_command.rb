# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class PasswordCommand < Command
    command_metadata(
      short_string: 'pa',
      long_string:  'password',
      description:  'show the stored password for a preferred WiFi network',
      usage:        'Usage: wifi-wand password <network-name>'
    )

    binds :model, output_support: :output_support

    def call(network)
      password = model.preferred_network_password(network)
      human_readable_string_producer = -> do
        if password
          <<~MESSAGE.chomp
            Preferred network "#{network}" stored password is "#{password}".
          MESSAGE
        else
          <<~MESSAGE.chomp
            Preferred network "#{network}" has no stored password.
          MESSAGE
        end
      end
      output_support.handle_output(password, human_readable_string_producer)
    end
  end
end
