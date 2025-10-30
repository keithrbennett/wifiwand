# frozen_string_literal: true

require_relative '../version'
require_relative '../timing_constants'

module WifiWand
  class CommandLineInterface
    module HelpSystem
      
      # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
      def help_text
        resource_help = model ? model.resource_manager.open_resources.help_string : "[resources unavailable]"
        
        %Q{
Command Line Switches     [wifi-wand version #{WifiWand::VERSION} at https://github.com/keithrbennett/wifiwand]
---------------------
-h, --help                - show this help message
-o, --output_format {i,j,k,p,y}
                          - when not in shell mode, outputs data in the following formats: inspect, JSON, pretty JSON, puts, YAML
-p, --wifi-interface interface_name
                          - specify WiFi interface name (overrides auto-detection)
-s, --shell               - run in shell mode (interactive pry REPL session)
-v, --[no-]verbose        - verbose mode (prints OS commands and their outputs)

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
lo[g]                     - start event logging (polls WiFi status, logs changes)
                            options: --interval N (default 5 seconds), --file [PATH] (default: wifiwand-events.log),
                                     --stdout (keep stdout when other destinations are used), --hook PATH (script to execute on events)
                            Logs events: WiFi on/off, network connect/disconnect, internet on/off
                            Ctrl+C to stop
na[meservers]             - nameservers: 'show' or no arg to show, 'clear' to clear,
                            or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
ne[twork_name]            - name (SSID) of currently connected WiFi network
on                        - turns WiFi on
of[f]                     - turns WiFi off
pa[ssword] network-name   - password for preferred network name
pr[ef_nets]               - preferred (saved) networks
q[uit]                    - exits this program (interactive shell mode only) (same as 'x')
qr [filespec|'-'] [password]
                          - generate a Wi‑Fi QR code; default PNG file <SSID>-qr-code.png; '-' prints ANSI QR to stdout; '.svg'/' .eps' use those formats; optional password avoids macOS auth prompt
ro[pen]                   - open web resources: #{resource_help}
s[tatus]                  - status line (WiFi, Network, TCP, DNS, Internet)
t[ill]                    - wait until state is reached:
                            Usage: till conn|disc|on|off [timeout_secs] [interval_secs]
                            conn/disc = Internet connected?/disconnected; on/off = Wi‑Fi power state
                            Defaults: timeout = wait indefinitely; interval = #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL}
                            Examples: "till off 20"  "till off 30 0.5"
w[ifi_on]                 - is the WiFi on?
x[it]                     - exits this program (interactive shell mode only) (same as 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`, e.g. `%ls`.
  * To display the QR code in the shell, pass the string returned by `qr :-` to `puts`. Ex: `puts(qr :-)`

}
      end

      def print_help
        dest = if respond_to?(:interactive_mode) && interactive_mode
                 $stdout
               else
                 respond_to?(:out_stream) ? out_stream : ($stdout)
               end
        dest.puts help_text
      end

      def help_hint
        "Use 'wifi-wand help' or 'wifi-wand -h' for help."
      end
    end
  end
end
