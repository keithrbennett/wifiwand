# frozen_string_literal: true

require_relative 'base'
require_relative 'avail_nets'
require_relative 'ci'
require_relative 'connect'
require_relative 'cycle'
require_relative 'disconnect'
require_relative 'forget'
require_relative 'help'
require_relative 'info'
require_relative 'log'
require_relative 'nameservers'
require_relative 'network_name'
require_relative 'off'
require_relative 'on'
require_relative 'password'
require_relative 'pref_nets'
require_relative 'public_ip'
require_relative 'qr'
require_relative 'quit'
require_relative 'ropen'
require_relative 'shell'
require_relative 'status'
require_relative 'till'
require_relative 'url'
require_relative 'wifi_on'

module WifiWand
  module Commands
    module Registry
      def commands
        @commands ||= [
          WifiWand::Commands::AvailNets.new,
          WifiWand::Commands::Ci.new,
          WifiWand::Commands::Connect.new,
          WifiWand::Commands::Cycle.new,
          WifiWand::Commands::Disconnect.new,
          WifiWand::Commands::Forget.new,
          WifiWand::Commands::Help.new,
          WifiWand::Commands::Info.new,
          WifiWand::Commands::Log.new,
          WifiWand::Commands::Nameservers.new,
          WifiWand::Commands::NetworkName.new,
          WifiWand::Commands::Off.new,
          WifiWand::Commands::On.new,
          WifiWand::Commands::Ropen.new,
          WifiWand::Commands::Password.new,
          WifiWand::Commands::PublicIp.new,
          WifiWand::Commands::PrefNets.new,
          WifiWand::Commands::Quit.new,
          WifiWand::Commands::Qr.new,
          WifiWand::Commands::Shell.new,
          WifiWand::Commands::Status.new,
          WifiWand::Commands::Till.new,
          WifiWand::Commands::Url.new,
          WifiWand::Commands::WifiOn.new,
        ]
      end

      def find_command(command_string)
        commands.detect { |command| command.aliases.include?(command_string) }
      end

      def resolve_command(command_string)
        command = find_command(command_string)
        command&.bind(self)
      end

      def find_command_action(command_string)
        command = resolve_command(command_string)
        command&.method(:call)
      end

      # Look up the command name and, if found, run it. If not, execute the passed block.
      def attempt_command_action(command_string, *, &error_handler_block)
        action = find_command_action(command_string)

        if action
          action.call(*)
        else
          error_handler_block.call
          nil
        end
      end
    end
  end
end
