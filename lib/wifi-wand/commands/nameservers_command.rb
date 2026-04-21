# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class NameserversCommand < Command
    SHORT_NAME = 'na'
    LONG_NAME = 'nameservers'
    DESCRIPTION = 'show, clear, or set DNS nameservers for the active WiFi connection'
    USAGE = 'Usage: wifi-wand nameservers [get|clear|IP ...]'

    binds :cli, :model

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
