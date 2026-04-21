# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class ConnectCommand
    SHORT_NAME = 'co'
    LONG_NAME = 'connect'
    DESCRIPTION = 'connect to a WiFi network, optionally using an explicit password'
    USAGE = 'Usage: wifi-wand connect <network> [password]'

    attr_reader :metadata, :model, :output, :interactive_mode

    def initialize(metadata: nil, model: nil, output: $stdout, interactive_mode: false)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @model = model
      @output = output
      @interactive_mode = interactive_mode
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(
        metadata:         metadata,
        model:            cli.model,
        output:           cli.send(:out_stream),
        interactive_mode: cli.interactive_mode
      )
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call(network, password = nil)
      model.connect(network, password)
      maybe_print_saved_password_message(network)
    end

    private def maybe_print_saved_password_message(network)
      return if interactive_mode
      return unless model.last_connection_used_saved_password?

      output.puts(
        "Using saved password for '#{network}'. " \
          "Use 'forget #{network}' if you need to use a different password."
      )
    end
  end
end
