# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class UrlCommand < Command
    command_metadata(
      short_string: 'u',
      long_string:  'url',
      description:  'project repository URL',
      usage:        'Usage: wifi-wand url'
    )

    PROJECT_URL = 'https://github.com/keithrbennett/wifiwand'

    def call = PROJECT_URL
  end
end
