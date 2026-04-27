# frozen_string_literal: true

require_relative '../version'
require_relative '../timing_constants'
require_relative '../models/helpers/resource_manager'

module WifiWand
  class CommandLineInterface
    module HelpSystem
      HORIZONTAL_RULE = '-' * 100
      REPOSITORY_URL = 'https://github.com/keithrbennett/wifiwand'
      HELP_BODY_WIDTH = 100
      HELP_LEFT_COLUMN_WIDTH = 34
      HELP_GAP = '  '
      HELP_LEADER = '.'
      HELP_DESCRIPTION_WIDTH = HELP_BODY_WIDTH - HELP_LEFT_COLUMN_WIDTH - HELP_GAP.length
      HELP_INDENT = '  '
      HELP_DESCRIPTION_INDENT = HELP_INDENT + (' ' * HELP_LEFT_COLUMN_WIDTH) + HELP_GAP

      HELP_SWITCHES = [
        ['-h, --help', 'show this help message'],
        [
          '-o, --output_format {i,j,k,p,y}',
          'when not in shell mode, outputs data in the following formats: ' \
            'inspect, JSON, pretty JSON, puts, YAML',
        ],
        [
          '-p, --wifi-interface interface_name',
          'specify WiFi interface name (overrides auto-detection)',
        ],
        ['-V, --version', 'show version'],
        ['-v, --[no-]verbose', 'verbose mode (prints OS commands and their outputs)'],
      ].freeze

      HELP_SUBCOMMANDS = [
        ['shell', 'start interactive shell (interactive pry REPL session)'],
      ].freeze

      # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
      def help_text
        resource_help = resource_manager.open_resources.help_string
        commands = help_commands(resource_help)

        body = [
          HORIZONTAL_RULE,
          format_header_line('Usage', 'wifi-wand [options] [subcommand] [args]'),
          format_header_line('Repository', REPOSITORY_URL),
          format_header_line('Version', WifiWand::VERSION),
          HORIZONTAL_RULE,
          nil,
          nil,
          section('Command Line Switches', HELP_SWITCHES),
          nil,
          nil,
          section('Subcommands', HELP_SUBCOMMANDS),
          nil,
          nil,
          'Commands',
          '--------',
          nil,
          format_entries(commands),
          nil,
          nil,
          'When in interactive shell mode:',
          format_lines([
            'remember to quote string literals.',
            'for pry commands, use prefix `%`, e.g. `%ls`.',
            'To display the QR code in the shell, pass the string returned by `qr :-` to `puts`. ' \
              'Ex: `puts(qr :-)`',
          ], bullet: '*'),
          nil,
        ].map { |entry| entry.nil? ? '' : entry }.join("\n")

        "#{body}\n"
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

      private def resource_manager
        @resource_manager ||= WifiWand::Helpers::ResourceManager.new
      end

      private def help_commands(resource_help)
        [
          ['a / avail_nets', 'array of names returned by the OS WiFi scan'],
          ['ci', 'Internet connectivity state: reachable, unreachable, or indeterminate'],
          [
            'co / connect network-name',
            [
              'connects to the specified network-name, turning WiFi on if necessary',
              'Note: returns once the SSID is associated, not when DNS/Internet are ready.',
              'To guarantee full connectivity, follow with: till internet_on [timeout_secs]',
            ],
          ],
          ['cy / cycle', 'toggles WiFi on/off state twice, regardless of starting state'],
          [
            'd / disconnect',
            [
              'disconnects from current network, does not turn off WiFi',
              'macOS note: a preferred network may auto-reassociate immediately after disconnect;',
              'if you need disconnect to stay effective, use `forget` on that network after joining it',
            ],
          ],
          [
            'f / forget name1 [..name_n]',
            [
              'removes network-name(s) from the preferred (saved) networks list',
              'in interactive mode, can be a single array of names, e.g. returned by `pref_nets`',
              'Example: `wifi-wand connect foo && wifi-wand forget foo` (no sleep normally needed)',
            ],
          ],
          ['h / help', 'prints this help'],
          ['i / info', 'a hash of detailed networking information'],
          [
            'lo / log',
            [
              'start event logging (monitors wifi on/off, connected/disconnected, internet on/off)',
              'options: --interval N (default 5 seconds), --file [PATH] (default: wifiwand-events.log),',
              '--stdout (keep stdout when file destination is used)',
              'Logs events: wifi on/off, connected/disconnected, internet on/off',
              'Internet events are derived from reachable/unreachable state; ' \
                'indeterminate is preserved as unknown',
              'Ctrl+C to stop',
            ],
          ],
          [
            'na / nameservers',
            [
              "nameservers: 'show' or no arg to show, 'clear' to clear,",
              "or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'",
            ],
          ],
          ['ne / network_name', 'name (SSID) of currently connected WiFi network'],
          ['on', 'turns WiFi on'],
          ['of / off', 'turns WiFi off'],
          ['pa / password network-name', 'password for preferred network name'],
          [
            'pi / public_ip [address|country|both|a|c|b]',
            [
              'public IP lookup; selectors may use long or short form,',
              "e.g. 'public_ip a' or 'pi country'; both (b) is the default",
            ],
          ],
          ['pr / pref_nets', 'preferred (saved) networks'],
          ['q / quit', "exits this program (interactive shell mode only) (same as 'x')"],
          [
            "qr [filespec|'-'] [password]",
            [
              "generate a Wi-Fi QR code; default PNG file <SSID>-qr-code.png; '-' prints ANSI QR to stdout;",
              "'.svg' / '.eps' use those formats; optional password avoids macOS auth prompt",
            ],
          ],
          ['ro / ropen', "open web resources: #{resource_help}"],
          [
            's / status',
            'status line (WiFi, Network, DNS, Internet; shows captive portal warning if login is required)',
          ],
          [
            't / till',
            [
              'wait until state is reached:',
              'Usage: till <state> [timeout_secs] [interval_secs]',
              'States:',
              'wifi_on        - WiFi hardware powered on',
              'wifi_off       - WiFi hardware powered off',
              'associated     - WiFi associated with an SSID (WiFi layer)',
              'disassociated  - WiFi not associated with any SSID',
              'internet_on    - Internet connectivity state is reachable',
              'internet_off   - Internet connectivity state is unreachable',
              "Defaults: timeout = wait indefinitely; interval = #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL}",
              'Examples: "till wifi_off 20"  "till internet_on 30 0.5"',
              "Migration: old 'conn' -> 'internet_on' or 'associated'; old 'disc' -> 'internet_off' or " \
                "'disassociated';",
              "old 'on' -> 'wifi_on'; old 'off' -> 'wifi_off'",
            ],
          ],
          ['w / wifi_on', 'is the WiFi on?'],
          ['x / xit', "exits this program (interactive shell mode only) (same as 'q')"],
        ]
      end

      private def section(title, entries)
        [title, '-' * title.length, nil, format_entries(entries)].map do |entry|
          entry.nil? ? '' : entry
        end.join("\n")
      end

      private def format_entries(entries)
        entries.flat_map { |label, description| format_entry(label, description) }.join("\n")
      end

      private def format_entry(label, description)
        wrapped_lines = wrap_entry_description(description)
        first_line, *rest = wrapped_lines

        if label.length <= HELP_LEFT_COLUMN_WIDTH
          [
            "#{HELP_INDENT}#{label_with_leader(label)}#{HELP_GAP}#{first_line}",
            *rest.map { |line| "#{HELP_DESCRIPTION_INDENT}#{line}" },
          ]
        else
          [
            "#{HELP_INDENT}#{label}",
            "#{HELP_DESCRIPTION_INDENT}#{first_line}",
            *rest.map { |line| "#{HELP_DESCRIPTION_INDENT}#{line}" },
          ]
        end
      end

      private def wrap_entry_description(description)
        descriptions = Array(description)
        descriptions.flat_map.with_index do |text, index|
          lines = wrap_text(text, HELP_DESCRIPTION_WIDTH)
          index.zero? ? lines : [nil, *lines]
        end.compact
      end

      private def wrap_text(text, width)
        words = text.split(/\s+/)
        return [''] if words.empty?

        lines = [String.new]

        words.each do |word|
          current_line = lines.last
          separator = current_line.empty? ? '' : ' '

          if current_line.length + separator.length + word.length <= width
            current_line << separator << word
          else
            lines << word.dup
          end
        end

        lines
      end

      private def format_lines(lines, bullet: nil)
        lines.flat_map do |line|
          prefix = bullet ? "#{HELP_INDENT}#{bullet} " : HELP_INDENT
          wrap_text(line, HELP_BODY_WIDTH - prefix.length).map.with_index do |wrapped_line, index|
            line_prefix = index.zero? ? prefix : (' ' * prefix.length)
            "#{line_prefix}#{wrapped_line}"
          end
        end.join("\n")
      end

      private def format_header_line(label, value)
        "#{label}:".ljust(23) + value
      end

      private def label_with_leader(label)
        padding_width = HELP_LEFT_COLUMN_WIDTH - label.length
        return label if padding_width <= 0

        "#{label} #{HELP_LEADER * (padding_width - 1)}"
      end
    end
  end
end
