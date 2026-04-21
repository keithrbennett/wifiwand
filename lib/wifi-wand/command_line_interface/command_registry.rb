# frozen_string_literal: true

require_relative '../commands/command'
require_relative '../commands/log_command'

module WifiWand
  class CommandLineInterface
    module CommandRegistry
      def commands
        @commands ||= [
          method_command('a',  'avail_nets',   :cmd_a),
          method_command('ci', 'ci',           :cmd_ci),
          method_command('co', 'connect',      :cmd_co),
          method_command('cy', 'cycle',        :cmd_cy),
          method_command('d',  'disconnect',   :cmd_d),
          method_command('f',  'forget',       :cmd_f),
          method_command('h',  'help',         :cmd_h),
          method_command('i',  'info',         :cmd_i),
          WifiWand::LogCommand.new,
          method_command('na', 'nameservers',  :cmd_na),
          method_command('ne', 'network_name', :cmd_ne),
          method_command('of', 'off',          :cmd_of),
          method_command('on', 'on',           :cmd_on),
          method_command('ro', 'ropen',        :cmd_ro),
          method_command('pa', 'password',     :cmd_pa),
          method_command('pi', 'pi',           :cmd_public_ip),
          method_command('pr', 'pref_nets',    :cmd_pr),
          method_command('pu', 'public_ip',    :cmd_public_ip),
          method_command('q',  'quit',         :cmd_q),
          method_command('qr', 'qr',           :cmd_qr),
          method_command('s',  'status',       :cmd_s),
          method_command('t',  'till',         :cmd_t),
          method_command('u',  'url',          :cmd_u),
          method_command('w',  'wifi_on',      :cmd_w),
          method_command('x',  'xit',          :cmd_x),
        ]
      end

      def find_command(command_string)
        commands.detect { |command| command.aliases.include?(command_string) }
      end

      def find_command_action(command_string)
        command = find_command(command_string)
        command&.bind(self)&.method(:call)
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
