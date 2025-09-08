require_relative '../version'
require_relative '../timing_constants'

module WifiWand
  class CommandLineInterface
    module HelpSystem
      
      # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
      def help_text
        resource_help = model ? model.resource_manager.open_resources.help_string : "[resources unavailable]"
        
        "
Command Line Switches     [wifi-wand version #{WifiWand::VERSION} at https://github.com/keithrbennett/wifiwand]
---------------------
-o {i,j,k,p,y}            - when not in shell mode, outputs data in the following formats: inspect, JSON, pretty JSON, puts, YAML
-p wifi_interface_name    - specify WiFi interface name (overrides auto-detection)
-s                        - run in shell mode (interactive pry REPL session)
-v                        - verbose mode (prints OS commands and their outputs)

Commands
--------
a[vail_nets]              - array of names of the available networks
ci                        - state of Internet connectivity, defined as both DNS and TCP working
co[nnect] network-name    - connects to the specified network-name, turning WiFi on if necessary
cy[cle]                   - toggles WiFi on/off state twice, regardless of starting state
d[isconnect]              - disconnects from current network, does not turn off WiFi
f[orget] name1 [..name_n] - removes network-name(s) from the preferred (saved) networks list
                            in interactive mode, can be a single array of names, e.g. returned by `pref_nets`
h[elp]                    - prints this help
i[nfo]                    - a hash of detailed networking information
na[meservers]             - nameservers: 'show' or no arg to show, 'clear' to clear,
                            or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
ne[twork_name]            - name (SSID) of currently connected WiFi network
on                        - turns WiFi on
of[f]                     - turns WiFi off
pa[ssword] network-name   - password for preferred network name
pr[ef_nets]               - preferred (saved) networks
q[uit]                    - exits this program (interactive shell mode only) (same as 'x')
qr [filespec|'-']         - generate QR for current Wi‑Fi; default PNG file <SSID>-qr-code.png; '-' prints ANSI QR to stdout; '.svg'/' .eps' use those formats
ro[pen]                   - open web resources: #{resource_help}
s[tatus]                  - status line (WiFi, Network, TCP, DNS, Internet)
t[ill]                    - wait until Internet connection reaches desired state:
                            'on'/:on (connected), 'off'/:off (disconnected), 'conn'/:conn (connected), 'disc'/:disc (disconnected)
                            Optional: wait interval between checks in seconds (default: #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL})
w[ifi_on]                 - is the WiFi on?
x[it]                     - exits this program (interactive shell mode only) (same as 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`, e.g. `%ls`.

"
      end

      def print_help
        puts help_text
      end

      def help_hint
        "Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end
    end
  end
end
