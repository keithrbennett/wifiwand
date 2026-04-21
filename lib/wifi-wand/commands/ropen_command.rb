# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class RopenCommand
    SHORT_NAME = 'ro'
    LONG_NAME = 'ropen'
    DESCRIPTION = 'open web resources'
    USAGE = 'Usage: wifi-wand ropen [resource_code ...]'

    attr_reader :metadata, :cli, :model, :interactive_mode, :out_stream, :err_stream

    def initialize(metadata: nil, cli: nil, model: nil, interactive_mode: nil, out_stream: nil,
      err_stream: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @model = model
      @interactive_mode = interactive_mode
      @out_stream = out_stream
      @err_stream = err_stream
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(
        metadata:         metadata,
        cli:              cli,
        model:            cli.model,
        interactive_mode: cli.interactive_mode,
        out_stream:       cli.out_stream,
        err_stream:       cli.err_stream
      )
    end

    def help_text
      base = <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP

      if model
        "#{base}

#{model.available_resources_help}"
      else
        base
      end
    end

    def call(*resource_codes)
      if resource_codes.empty?
        if interactive_mode
          model.available_resources_help
        else
          out_stream.puts(model.available_resources_help)
          nil
        end
      else
        result = model.open_resources_by_codes(*resource_codes)

        unless result[:invalid_codes].empty?
          err_stream.puts(model.resource_manager.invalid_codes_error(result[:invalid_codes]))
        end

        nil
      end
    end
  end
end
