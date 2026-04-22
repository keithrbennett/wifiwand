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
      # Standard command classes can declare their names and help text once here
      # instead of repeating the same metadata object construction in `initialize`.
      def command_metadata(short_string:, long_string:, description: nil, usage: nil)
        @declared_metadata = CommandMetadata.new(
          short_string: short_string,
          long_string:  long_string,
          description:  description,
          usage:        usage
        )
      end

      # Command subclasses look here first for their metadata declaration; the
      # constant-based fallback stays in place so older or specialized commands
      # can keep working until they are migrated.
      def declared_metadata
        return @declared_metadata if instance_variable_defined?(:@declared_metadata)

        superclass.respond_to?(:declared_metadata) ? superclass.declared_metadata : nil
      end

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

    attr_reader :metadata, :cli

    def initialize(metadata: nil, cli: nil, **attributes)
      @metadata = metadata || default_metadata
      @cli = cli
      assign_attributes(attributes)
    end

    def aliases
      metadata.aliases
    end

    # Turn a registered command definition into the executable command object
    # for this CLI invocation by copying the declared bound attributes from `cli`.
    def bind(cli)
      self.class.new(metadata: metadata, **bound_attributes_for(cli))
    end

    def help_text
      return metadata.usage unless metadata.description

      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    private def assign_attributes(attributes)
      attributes.each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    private def default_metadata
      self.class.declared_metadata || metadata_from_constants
    end

    private def metadata_from_constants
      # Keep supporting the older constant-based declaration style so command
      # classes can move over incrementally.
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
