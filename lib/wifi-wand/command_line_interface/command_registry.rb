# frozen_string_literal: true

require_relative '../commands/command'
require_relative '../commands/avail_nets_command'
require_relative '../commands/ci_command'
require_relative '../commands/connect_command'
require_relative '../commands/cycle_command'
require_relative '../commands/disconnect_command'
require_relative '../commands/forget_command'
require_relative '../commands/help_command'
require_relative '../commands/info_command'
require_relative '../commands/log_command'
require_relative '../commands/nameservers_command'
require_relative '../commands/network_name_command'
require_relative '../commands/off_command'
require_relative '../commands/on_command'
require_relative '../commands/password_command'
require_relative '../commands/pref_nets_command'
require_relative '../commands/public_ip_command'
require_relative '../commands/qr_command'
require_relative '../commands/quit_command'
require_relative '../commands/ropen_command'
require_relative '../commands/status_command'
require_relative '../commands/till_command'
require_relative '../commands/url_command'
require_relative '../commands/wifi_on_command'

module WifiWand
  class CommandLineInterface
    module CommandRegistry
      def commands
        @commands ||= [
          WifiWand::AvailNetsCommand.new,
          WifiWand::CiCommand.new,
          WifiWand::ConnectCommand.new,
          WifiWand::CycleCommand.new,
          WifiWand::DisconnectCommand.new,
          WifiWand::ForgetCommand.new,
          WifiWand::HelpCommand.new,
          WifiWand::InfoCommand.new,
          WifiWand::LogCommand.new,
          WifiWand::NameserversCommand.new,
          WifiWand::NetworkNameCommand.new,
          WifiWand::OffCommand.new,
          WifiWand::OnCommand.new,
          WifiWand::RopenCommand.new,
          WifiWand::PasswordCommand.new,
          WifiWand::PublicIpCommand.new,
          WifiWand::PrefNetsCommand.new,
          WifiWand::QuitCommand.new,
          WifiWand::QrCommand.new,
          WifiWand::StatusCommand.new,
          WifiWand::TillCommand.new,
          WifiWand::UrlCommand.new,
          WifiWand::WifiOnCommand.new,
        ]
      end

      def find_command(command_string)
        commands.detect { |command| command.aliases.include?(command_string) }
      end

      def find_bound_command(command_string)
        command = find_command(command_string)
        command&.bind(self)
      end

      def find_command_action(command_string)
        command = find_bound_command(command_string)
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
