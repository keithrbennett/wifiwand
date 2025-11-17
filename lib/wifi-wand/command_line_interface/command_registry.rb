# frozen_string_literal: true

module WifiWand
  class CommandLineInterface
    module CommandRegistry

      class Command < Struct.new(:min_string, :max_string, :action); end

      def commands
        @commands_ ||= [
            Command.new('a',   'avail_nets',    -> (*_options) { cmd_a             }),
            Command.new('ci',  'ci',            -> (*_options) { cmd_ci            }),
            Command.new('co',  'connect',       -> (*options)  { cmd_co(*options)  }),
            Command.new('cy',  'cycle',         -> (*_options) { cmd_cy            }),
            Command.new('d',   'disconnect',    -> (*_options) { cmd_d             }),
            Command.new('f',   'forget',        -> (*options)  { cmd_f(*options)   }),
            Command.new('h',   'help',          -> (*_options) { cmd_h             }),
            Command.new('i',   'info',          -> (*_options) { cmd_i             }),
            Command.new('lo',  'log',           -> (*options)  { cmd_log(*options) }),
            Command.new('na',  'nameservers',   -> (*options)  { cmd_na(*options)  }),
            Command.new('ne',  'network_name',  -> (*_options) { cmd_ne            }),
            Command.new('of',  'off',           -> (*_options) { cmd_of            }),
            Command.new('on',  'on',            -> (*_options) { cmd_on            }),
            Command.new('ro',  'ropen',         -> (*options)  { cmd_ro(*options)  }),
            Command.new('pa',  'password',      -> (*options)  { cmd_pa(*options)  }),
            Command.new('pr',  'pref_nets',     -> (*_options) { cmd_pr            }),
            Command.new('q',   'quit',          -> (*_options) { cmd_q             }),
            Command.new('qr',  'qr',            -> (*options)  { cmd_qr(*options)  }),
            Command.new('s',   'status',        -> (*_options) { cmd_s             }),
            Command.new('t',   'till',          -> (*options)  { cmd_t(*options)   }),
            Command.new('u',   'url',           -> (*_options) { PROJECT_URL       }),
            Command.new('w',   'wifi_on',       -> (*_options) { cmd_w             }),
            Command.new('x',   'xit',           -> (*_options) { cmd_x             })
        ]
      end

      def find_command_action(command_string)
        result = commands.detect do |cmd|
          cmd.max_string.start_with?(command_string) \
          && \
          command_string.length >= cmd.min_string.length  # e.g. 'c' by itself should not work
        end
        result ? result.action : nil
      end

      # Look up the command name and, if found, run it. If not, execute the passed block.
      def attempt_command_action(command, *args, &error_handler_block)
        action = find_command_action(command)

        if action
          action.(*args)
        else
          error_handler_block.call
          nil
        end
      end
    end
  end
end
