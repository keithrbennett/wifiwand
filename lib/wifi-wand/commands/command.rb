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
    class << self
      # Declare which values a bound command instance should pull from the CLI.
      # `binds :model` copies `cli.model`, while `binds output: :out_stream` maps
      # a command attribute name to a different CLI reader.
      def binds(*attributes, **mapped_attributes)
        @binding_sources ||= {}

        attributes.each do |attribute|
          @binding_sources[attribute] = attribute
        end

        mapped_attributes.each do |attribute, source|
          @binding_sources[attribute] = source
        end

        attr_reader(*@binding_sources.keys)
      end

      # Subclasses inherit their parents' binding declarations so specialized
      # commands can add to the shared binding set instead of replacing it.
      def binding_sources
        inherited_sources = superclass.respond_to?(:binding_sources) ? superclass.binding_sources : {}
        inherited_sources.merge(@binding_sources || {})
      end
    end

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

    # Turn a registered command definition into the executable command object
    # for this CLI invocation by copying the declared bound attributes from `cli`.
    # The base `Command` class keeps its older handler-based path for the generic
    # registry spec and compatibility callers.
    def bind(cli)
      if instance_of?(Command)
        return self.class.new(metadata: metadata, handler_name: handler_name,
          cli: cli)
      end

      self.class.new(metadata: metadata, **bound_attributes_for(cli))
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

    private def bound_attributes_for(cli)
      # A `:cli` binding injects the whole CLI object; any other symbol reads the
      # corresponding method from the CLI and assigns that value to the command.
      self.class.binding_sources.transform_values do |source|
        source == :cli ? cli : cli.public_send(source)
      end
    end
  end
end
