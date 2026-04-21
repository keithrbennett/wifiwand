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
    attr_reader :metadata, :handler_name, :cli

    def initialize(metadata: nil, handler_name: nil, cli: nil, **attributes)
      @metadata = metadata || default_metadata
      @handler_name = handler_name
      @cli = cli
      assign_attributes(attributes)
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, handler_name: handler_name, cli: cli)
    end

    def help_text
      return metadata.usage unless metadata.description

      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call(*)
      cli.public_send(handler_name, *)
    end

    private def assign_attributes(attributes)
      attributes.each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    private def default_metadata
      CommandMetadata.new(
        short_string: self.class::SHORT_NAME,
        long_string:  self.class::LONG_NAME,
        description:  self.class::DESCRIPTION,
        usage:        self.class::USAGE
      )
    end
  end
end
