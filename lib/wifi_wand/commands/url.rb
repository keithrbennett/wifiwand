# frozen_string_literal: true

require_relative 'base'
require_relative '../project_url'

module WifiWand
  module Commands
    class Url < Base
      command_metadata(
        short_string: 'u',
        long_string:  'url',
        description:  'project repository URL',
        usage:        'Usage: wifiwand url'
      )

      binds output_support: :output_support
      allow_invocation_options :output_format

      def call(*args)
        validate_max_arguments!(args, 0)

        output_support.handle_output(WifiWand::PROJECT_URL, -> { WifiWand::PROJECT_URL })
      end
    end
  end
end
