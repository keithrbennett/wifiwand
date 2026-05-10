# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class NameserversCommand < Command
    RESERVED_SUBCOMMANDS = %w[get clear].freeze

    command_metadata(
      short_string: 'na',
      long_string:  'nameservers',
      description:  'show, clear, or set DNS nameservers for the active WiFi connection',
      usage:        'Usage: wifi-wand nameservers [get|clear|IP ...]'
    )

    binds :model, output_support: :output_support

    def call(*args)
      subcommand = subcommand_for(args)

      case subcommand
      when :get
        current_nameservers = model.nameservers
        output_support.handle_output(current_nameservers, human_readable_string_producer(current_nameservers))
      when :clear
        model.set_nameservers(:clear)
        output_support.handle_output([], -> { 'Nameservers cleared.' })
      when :put
        nameservers = model.set_nameservers(args)
        output_support.handle_output(nameservers, -> { "Nameservers set to: #{nameservers.join(', ')}" })
      end
    end

    private def subcommand_for(args)
      first_arg = args.first.to_s

      if args.empty?
        :get
      elsif first_arg == 'get'
        validate_max_arguments!(args, 1)
        :get
      elsif first_arg == 'clear'
        validate_max_arguments!(args, 1)
        :clear
      else
        validate_no_reserved_subcommand_arguments!(args)
        :put
      end
    end

    private def validate_no_reserved_subcommand_arguments!(args)
      reserved_argument = args.map(&:to_s).find { |arg| RESERVED_SUBCOMMANDS.include?(arg) }
      return unless reserved_argument

      raise WifiWand::ConfigurationError,
        "Invalid nameserver argument '#{reserved_argument}'. " \
          "'get' and 'clear' are reserved nameservers subcommands.\n#{metadata.usage}"
    end

    private def human_readable_string_producer(current_nameservers)
      -> do
        nameservers_list = current_nameservers.empty? ? '[None]' : current_nameservers.join(', ')
        "Nameservers: #{nameservers_list}"
      end
    end
  end
end
