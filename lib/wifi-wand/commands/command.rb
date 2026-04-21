# frozen_string_literal: true

module WifiWand
  class CommandMetadata
    attr_reader :short_string, :long_string

    def initialize(short_string:, long_string:)
      @short_string = short_string
      @long_string = long_string
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
