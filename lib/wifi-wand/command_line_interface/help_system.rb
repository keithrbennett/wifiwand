require_relative '../version'
require_relative '../timing_constants'

module WifiWand
  class CommandLineInterface
    module HelpSystem
      
      # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
      def help_text
        resource_help = model ? model.resource_manager.open_resources.help_string : "[resources unavailable]"
        
        "
Command Line Switches:                    [wifi-wand version #{WifiWand::VERSION} at https://github.com/keithrbennett/wifiwand]

-o {i,j,k,p,y}            - outputs data in inspect, JSON, pretty JSON, puts, or YAML format when not in shell mode
-p wifi_interface_name    - override automatic detection of interface name with this name
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:

a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
cy[cle]                   - turns wifi off, then on, preserving network selection
d[isconnect]              - disconnects from current network, does not turn off wifi
f[orget] name1 [..name_n] - removes network-name(s) from the preferred networks list
                            in interactive mode, can be a single array of names, e.g. returned by `pref_nets`
h[elp]                    - prints this help
i[nfo]                    - a hash of wifi-related information
na[meservers]             - nameservers: 'show' or no arg to show, 'clear' to clear,
                            or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
ne[twork_name]            - name (SSID) of currently connected network
on                        - turns wifi on
of[f]                     - turns wifi off
pa[ssword] network-name   - password for preferred network-name
pr[ef_nets]               - preferred (saved) networks
q[uit]                    - exits this program (interactive shell mode only) (see also 'x')
ro[pen]                   - open resource (#{resource_help})
s[tatus]                  - status line (WiFi, Network, TCP, DNS, Internet)
t[ill]                    - returns when the desired Internet connection state is true. Options:
                            1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                            2) wait interval between tests, in seconds (optional, defaults to #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL} seconds)
w[ifi_on]                 - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`.

"
      end

      def print_help
        puts help_text
      end

      def print_help_hint
        puts "Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end
    end
  end
end