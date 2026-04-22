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

    binds :cli, :model

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
      cli.send(:handle_output, password, human_readable_string_producer)
    end
  end
end
