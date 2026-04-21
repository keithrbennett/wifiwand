# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class UrlCommand
    SHORT_NAME = 'u'
    LONG_NAME = 'url'
    DESCRIPTION = 'project repository URL'
    USAGE = 'Usage: wifi-wand url'
    PROJECT_URL = 'https://github.com/keithrbennett/wifiwand'

    attr_reader :metadata

    def initialize(metadata: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
    end

    def aliases
      metadata.aliases
    end

    def bind(_cli)
      self
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call = PROJECT_URL
  end
end
