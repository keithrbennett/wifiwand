# frozen_string_literal: true

require_relative '../version'
require_relative '../timing_constants'

module WifiWand
  class CommandLineInterface
    module HelpSystem
      HORIZONTAL_RULE = '-' * 79
      REPOSITORY_URL = 'https://github.com/keithrbennett/wifiwand'

      # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
      def help_text
        resource_help = model ? model.resource_manager.open_resources.help_string : '[resources unavailable]'

        <<~HELPTEXT
          #{HORIZONTAL_RULE}
          Usage:                 wifi-wand [options] [subcommand] [args]
          Repository:            #{REPOSITORY_URL}
          Version:               #{WifiWand::VERSION}
          #{HORIZONTAL_RULE}

          Command Line Switches
          ---------------------
          -h, --help                - show this help message
          -o, --output_format {i,j,k,p,y}
                                    - when not in shell mode, outputs data in the following formats: inspect, JSON, pretty JSON, puts, YAML
          -p, --wifi-interface interface_name
                                    - specify WiFi interface name (overrides auto-detection)
          -V, --version             - show version
          -v, --[no-]verbose        - verbose mode (prints OS commands and their outputs)

          Subcommands
          -----------
          shell                     - start interactive shell (interactive pry REPL session)

          Commands
          --------
          Commands accept only the exact short or exact long form shown below.
          a / avail_nets          - array of names returned by the OS WiFi scan
          ci                        - Internet connectivity state: reachable, unreachable, or indeterminate
          co / connect network-name - connects to the specified network-name, turning WiFi on if necessary
          cy / cycle               - toggles WiFi on/off state twice, regardless of starting state
          d / disconnect          - disconnects from current network, does not turn off WiFi
                                      macOS note: a preferred network may auto-reassociate immediately after disconnect;
                                      if you need disconnect to stay effective, use `forget` on that network after joining it
          f / forget name1 [..name_n] - removes network-name(s) from the preferred (saved) networks list
                                      in interactive mode, can be a single array of names, e.g. returned by `pref_nets`
                                      Example: `wifi-wand connect foo && wifi-wand forget foo` (no sleep normally needed)
          h / help                - prints this help
          i / info                - a hash of detailed networking information
          lo / log                - start event logging (monitors wifi on/off, connected/disconnected, internet on/off)
                                      options: --interval N (default 5 seconds), --file [PATH] (default: wifiwand-events.log),
                                               --stdout (keep stdout when file destination is used)
                                      Logs events: wifi on/off, connected/disconnected, internet on/off
                                      Internet events are derived from reachable/unreachable state; indeterminate is preserved as unknown
                                      Ctrl+C to stop
          na / nameservers        - nameservers: 'show' or no arg to show, 'clear' to clear,
                                      or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
          ne / network_name       - name (SSID) of currently connected WiFi network
          on                        - turns WiFi on
          of / off                - turns WiFi off
          pa / password network-name - password for preferred network name
          pu / public_ip [address|country|both|a|c|b]
                                    - public IP lookup; selectors may use long or short form,
                                      e.g. 'public_ip a' or 'pi country'; both (b) is the default
          pi [address|country|both|a|c|b]
                                    - short alias for public_ip with the same selector forms
          pr / pref_nets          - preferred (saved) networks
          q / quit                - exits this program (interactive shell mode only) (same as 'x')
          qr [filespec|'-'] [password]
                                    - generate a Wi‑Fi QR code; default PNG file <SSID>-qr-code.png; '-' prints ANSI QR to stdout; '.svg'/' .eps' use those formats; optional password avoids macOS auth prompt
          ro / ropen              - open web resources: #{resource_help}
          s / status              - status line (WiFi, Network, DNS, Internet; shows captive portal warning if login is required)
          t / till                - wait until state is reached:
                                      Usage: till <state> [timeout_secs] [interval_secs]
                                      States:
                                        wifi_on        – WiFi hardware powered on
                                        wifi_off       – WiFi hardware powered off
                                        associated     – WiFi associated with an SSID (WiFi layer)
                                        disassociated  – WiFi not associated with any SSID
                                        internet_on    – Internet connectivity state is reachable
                                        internet_off   – Internet connectivity state is unreachable
                                      Defaults: timeout = wait indefinitely; interval = #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL}
                                      Examples: "till wifi_off 20"  "till internet_on 30 0.5"
                                      Migration: old 'conn'→'internet_on' or 'associated'; old 'disc'→'internet_off' or 'disassociated';
                                                 old 'on'→'wifi_on'; old 'off'→'wifi_off'
          w / wifi_on             - is the WiFi on?
          x / xit                 - exits this program (interactive shell mode only) (same as 'q')

          When in interactive shell mode:
            * remember to quote string literals.
            * for pry commands, use prefix `%`, e.g. `%ls`.
            * To display the QR code in the shell, pass the string returned by `qr :-` to `puts`. Ex: `puts(qr :-)`

        HELPTEXT
      end

      def print_help
        dest = if respond_to?(:interactive_mode) && interactive_mode
          $stdout
        else
          respond_to?(:out_stream) ? out_stream : $stdout
        end
        dest.puts help_text
      end

      def help_hint = "Use 'wifi-wand help' or 'wifi-wand -h' for help."
    end
  end
end
