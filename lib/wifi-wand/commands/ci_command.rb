# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class CiCommand
    SHORT_NAME = 'ci'
    LONG_NAME = 'ci'
    DESCRIPTION = 'Internet connectivity state: reachable, unreachable, or indeterminate'
    USAGE = 'Usage: wifi-wand ci'

    attr_reader :metadata, :cli, :model, :interactive_mode

    def initialize(metadata: nil, cli: nil, model: nil, interactive_mode: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @model = model
      @interactive_mode = interactive_mode
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(
        metadata:         metadata,
        cli:              cli,
        model:            cli.model,
        interactive_mode: cli.interactive_mode
      )
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call
      state = model.internet_connectivity_state
      output_value = interactive_mode ? state : state.to_s
      cli.send(:handle_output, output_value, -> { "Internet connectivity: #{state}" })
    end
  end
end
