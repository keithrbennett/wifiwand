# frozen_string_literal: true

require_relative 'command'
require_relative '../project_url'

module WifiWand
  class UrlCommand < Command
    command_metadata(
      short_string: 'u',
      long_string:  'url',
      description:  'project repository URL',
      usage:        'Usage: wifi-wand url'
    )

    binds output_support: :output_support

    def call
      output_support.handle_output(WifiWand::PROJECT_URL, -> { WifiWand::PROJECT_URL })
    end
  end
end
