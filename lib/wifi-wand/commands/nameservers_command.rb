# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class NameserversCommand
    SHORT_NAME = 'na'
    LONG_NAME = 'nameservers'
    DESCRIPTION = 'show, clear, or set DNS nameservers for the active WiFi connection'
    USAGE = 'Usage: wifi-wand nameservers [get|clear|IP ...]'

    attr_reader :metadata, :cli, :model

    def initialize(metadata: nil, cli: nil, model: nil)
      @metadata = metadata || CommandMetadata.new(
        short_string: SHORT_NAME,
        long_string:  LONG_NAME,
        description:  DESCRIPTION,
        usage:        USAGE
      )
      @cli = cli
      @model = model
    end

    def aliases
      metadata.aliases
    end

    def bind(cli)
      self.class.new(metadata: metadata, cli: cli, model: cli.model)
    end

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}
      HELP
    end

    def call(*args)
      subcommand = subcommand_for(args)

      case subcommand
      when :get
        current_nameservers = model.nameservers
        cli.send(:handle_output, current_nameservers, human_readable_string_producer(current_nameservers))
      when :clear
        model.set_nameservers(:clear)
      when :put
        model.set_nameservers(args)
      end
    end

    private def subcommand_for(args)
      if args.empty? || args.first.to_sym == :get
        :get
      elsif args.first.to_sym == :clear
        :clear
      else
        :put
      end
    end

    private def human_readable_string_producer(current_nameservers)
      -> do
        nameservers_list = current_nameservers.empty? ? '[None]' : current_nameservers.join(', ')
        "Nameservers: #{nameservers_list}"
      end
    end
  end
end
