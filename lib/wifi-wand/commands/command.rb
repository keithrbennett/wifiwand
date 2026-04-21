# frozen_string_literal: true

module WifiWand
  class CommandMetadata
    attr_reader :short_string, :long_string, :description, :usage

    def initialize(short_string:, long_string:, description: nil, usage: nil)
      @short_string = short_string
      @long_string = long_string
      @description = description
      @usage = usage
    end

    def aliases
      [short_string, long_string]
    end
  end

  class Command
    attr_reader :metadata, :cli, :handler_name

    def initialize(metadata:, handler_name:, cli: nil)
      @metadata = metadata
      @handler_name = handler_name
      @cli = cli
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, handler_name: handler_name, cli: cli)
    end

    def call(*)
      cli.public_send(handler_name, *)
    end
  end
end
