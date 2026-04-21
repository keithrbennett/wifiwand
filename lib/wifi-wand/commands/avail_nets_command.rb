# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class AvailNetsCommand
    SHORT_NAME = 'a'
    LONG_NAME = 'avail_nets'
    DESCRIPTION = 'list visible WiFi networks in descending signal-strength order'
    USAGE = 'Usage: wifi-wand avail_nets'

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

    def call
      info = model.available_network_names
      cli.send(:handle_output, info, human_readable_string_producer(info))
    rescue WifiWand::Error => e
      cli.send(:handle_output, nil, -> { e.message })
    end

    private def human_readable_string_producer(info)
      -> do
        if info.respond_to?(:empty?) && info.empty?
          cli.send(:empty_available_networks_message)
        else
          <<~MESSAGE
            Available networks, in descending signal strength order,
            as returned by the OS scan, are:

            #{cli.send(:format_object, info)}
          MESSAGE
        end
      end
    end
  end
end
