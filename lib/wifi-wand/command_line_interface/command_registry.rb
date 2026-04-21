# frozen_string_literal: true

require_relative '../commands/command'
require_relative '../commands/avail_nets_command'
require_relative '../commands/connect_command'
require_relative '../commands/cycle_command'
require_relative '../commands/disconnect_command'
require_relative '../commands/forget_command'
require_relative '../commands/help_command'
require_relative '../commands/log_command'
require_relative '../commands/nameservers_command'
require_relative '../commands/network_name_command'
require_relative '../commands/password_command'
require_relative '../commands/pref_nets_command'
require_relative '../commands/public_ip_command'
require_relative '../commands/till_command'

module WifiWand
  class CommandLineInterface
    module CommandRegistry
      def commands
        @commands ||= [
          WifiWand::AvailNetsCommand.new,
          method_command('ci', 'ci',           :cmd_ci),
          WifiWand::ConnectCommand.new,
          WifiWand::CycleCommand.new,
          WifiWand::DisconnectCommand.new,
          WifiWand::ForgetCommand.new,
          WifiWand::HelpCommand.new,
          method_command('i',  'info',         :cmd_i),
          WifiWand::LogCommand.new,
          WifiWand::NameserversCommand.new,
          WifiWand::NetworkNameCommand.new,
          method_command('of', 'off',          :cmd_of),
          method_command('on', 'on',           :cmd_on),
          method_command('ro', 'ropen',        :cmd_ro),
          WifiWand::PasswordCommand.new,
          WifiWand::PublicIpCommand.new,
          WifiWand::PrefNetsCommand.new,
          method_command('q',  'quit',         :cmd_q),
          method_command('qr', 'qr',           :cmd_qr),
          method_command('s',  'status',       :cmd_s),
          WifiWand::TillCommand.new,
          method_command('u',  'url',          :cmd_u),
          method_command('w',  'wifi_on',      :cmd_w),
          method_command('x',  'xit',          :cmd_x),
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

      private def method_command(short_string, long_string, handler_name)
        metadata = WifiWand::CommandMetadata.new(short_string: short_string, long_string: long_string)
        WifiWand::Command.new(metadata: metadata, handler_name: handler_name)
      end
    end
  end
end
