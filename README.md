![logo](logo/wifiwand-logo-horizontal-color.png)

# wifiwand

### Installation

**Requirements:** Ruby >= 3.2.0

To install this software, run:

`gem install wifi-wand`

or, you may need to precede that command with `sudo` to install it system-wide:

`sudo gem install wifi-wand`

**Note for macOS users:** macOS ships with Ruby 2.6. If you get an installation error about Ruby version or
the `traces` gem, install a modern Ruby. The simplest way is with Homebrew:

```bash
brew install ruby

# Add to ~/.zshrc or ~/.bash_profile:
# Apple Silicon Macs:
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

# Intel Macs:
export PATH="/usr/local/opt/ruby/bin:$PATH"
```

#### Ruby < 3.2 is unsupported

Ruby versions older than 3.2 are unsupported because the tracked source uses modern Ruby syntax and APIs. If
your system Ruby is too old, install a modern Ruby before installing `wifi-wand` (the gem name).

#### JRuby Compatibility

The test suite passes on JRuby, and to the best of our knowledge the project is fully JRuby-compatible.
If you encounter any JRuby-specific issues, please open a GitHub issue, including as much detail as possible.

#### Optional Dependency for QR Codes

- To use the `wifiwand qr` command for generating Wi‑Fi QR codes, install `qrencode`.
  - macOS: `brew install qrencode`
  - Ubuntu: `sudo apt install qrencode`

---

### Security Notes

`wifiwand` is intended for individual users on machines they control. Some workflows can expose WiFi
passwords to local surfaces such as shell history, process listings, verbose output, terminal scrollback, and
generated QR code files. See **[Security Notes](docs/SECURITY_NOTES.md)** for the full list of potential
exposure points and practical precautions.

---

### 🐧 Note for Ubuntu Users

Ubuntu support requires **NetworkManager** (standard on Ubuntu Desktop).
`wifiwand` uses `nmcli`, `iw`, and `ip` to manage WiFi.
These are typically pre-installed on Ubuntu systems.

---

### ⚠️ Important for macOS Users (14+)

**On macOS 14 or later, install the macOS helper application after gem installation:**

```bash
wifiwand-macos-setup
```

This installs the `wifiwand-helper` helper application and grants the Location Services permission needed for
unredacted WiFi network names. Without the helper application or its permission, network names may appear as
`<hidden>` or `<redacted>`. See the **[macOS Quick Start](docs/MACOS_QUICK_START.md)** for setup steps and
the **[macOS Helper App Details](docs/MACOS_HELPER_APP_DETAILS.md)** for behavior with redacted network
names.

---

### Description

The `wifiwand` gem enables the query and management
of WiFi configuration, environment, and behavior, on Mac and Ubuntu systems.
Internally, it uses OS-specific command line utilities to interact with the
underlying operating system -- for example, `networksetup`, `system_profiler`,
and `ifconfig` on macOS, and `nmcli`, `iw`, and `ip` on Ubuntu Linux.
However, the code encapsulates the OS-specific logic in model subclasses with identical
method names and argument lists, so that they present a unified interface for use in:

* command line invocation (e.g. `wifiwand co my-network my-password` to connect to a network)
* interactive shell (REPL) sessions where the wifiwand methods are effectively DSL commands (`wifiwand
  shell` to run in interactive mode)
* other Ruby applications as a gem (library) (`require 'wifi_wand'`)

### ⚠️ Important API Semantics: `connected?` Means WiFi Connected

In the Ruby API and interactive shell, `connected?` is WiFi-specific. It answers whether the WiFi interface
is connected or otherwise considered usable by the current OS-specific WiFi model.

It does not mean "this machine has network access by any route." If Ethernet is the only active uplink,
`connected?` may still return `false`. Use `internet_connectivity_state` when you need host-level internet
reachability instead of WiFi-interface state.

### ⚠️ Version 3 Breaking Changes

Version 3 includes API, CLI, and behavior changes that may require updates to
scripts or calling code.

See **[Version 3 Breaking Changes](docs/BREAKING_CHANGES_V3.md)** for the
canonical migration guide. Highlights include:

- `connected_to_internet?` replaced by `internet_connectivity_state`
- global `-v` / `--verbose` now requires an explicit boolean value, such as `-v true`
- legacy `till` wait-state aliases `on`/`off`/`conn`/`disc` replaced by explicit wait-state names
- `-s` / `--shell` replaced by the `shell` command
- partial CLI abbreviations removed; use exact short or long command names
- `WifiWand::Main#parse_command_line` removed from the public API

### Quick Start

```bash
# Display networking status (e.g.: WiFi: ON | WiFi Network: my_network | DNS: YES | Internet: YES)
wifiwand s

# Display WiFi on/off status
wifiwand w

# See available WiFi networks
wifiwand a

# Connect to a WiFi network with password
wifiwand co MyNetwork password

# Connect to a WiFi network without password (if no password required or network is saved/preferred
wifiwand co MyNetwork

# Force an open-network attempt even if a saved password exists
wifiwand co MyNetwork ''

# Display detailed networking information
wifiwand i

# Start interactive shell
wifiwand shell

# Display underlying OS calls and their output
wifiwand -v true ...
```

### Documentation

Start with the **[user documentation index](docs/README.md)** for the complete guide map.

Setup and platform guides:

- **[macOS Quick Start](docs/MACOS_QUICK_START.md)** - One-time setup for macOS Location Services access.
- **[Ubuntu Setup & Requirements](docs/UBUNTU_SETUP.md)** - NetworkManager and tool requirements for Ubuntu.
- **[Security Notes](docs/SECURITY_NOTES.md)** - Local WiFi password exposure surfaces and precautions.
- **[macOS Helper App Details](docs/MACOS_HELPER_APP_DETAILS.md)** - End-user details for the native macOS
  helper application.

Command-specific guides:

- **[Event Logging (`log` command)](docs/LOGGING.md)** - Continuously monitor WiFi state changes, log events
  over time, and detect network issues.
- **[Status Command](docs/STATUS_COMMAND.md)** - Understand WiFi and connectivity status display.
- **[Info Command](docs/INFO_COMMAND.md)** - Get detailed network configuration and status information.
- **[Connectivity Checking (`ci` command)](docs/CONNECTIVITY_CHECKING.md)** - Check internet availability in
  scripts and automation.
- **[DNS Configuration Guide](docs/DNS_Configuration_Guide.md)** - Managing nameservers and DNS settings.

Reference, migration, and history:

- **[Environment Variables Reference](docs/ENVIRONMENT_VARIABLES.md)** - Configuration via environment
  variables, including the `WIFIWAND_OPTS` default-options helper.
- **[Version 3 Breaking Changes](docs/BREAKING_CHANGES_V3.md)** - Required migration steps for version 3.
- **[Version 3.0 Changes](docs/CHANGELOG_V2_TO_V3.md)** - Broader version 3.0 change summary.
- **[Release Notes](RELEASE_NOTES.md)** - Historical release-by-release notes.

Maintainer documentation is available in the full source checkout under
**[dev/docs](dev/docs/README.md)**. Those files are not packaged with the gem, so that link is intended for
readers browsing the source repository rather than installed gem documentation.

### Usage

Available commands and options can be seen with generated help:

```bash
wifiwand --help
wifiwand help
```

The generated help is the canonical command reference and includes current boolean option forms, command
aliases, `log` event semantics, `status` wording, and `till` wait-state names.

Scripting note: `wifiwand connect` returns once the requested SSID is associated at the WiFi layer, not when
DNS or full internet connectivity is ready. To wait for internet readiness after joining, run:

```bash
wifiwand till internet_on 30
```

### Pretty Output

The `amazing_print` gem is used for formatting output nicely in both non-interactive and interactive (shell)
modes.

### JSON, YAML, and Other Output Formats

You can specify that output in _noninteractive_ mode be in a certain format.
Currently, JSON, pretty JSON, YAML, inspect, puts, pretty print, and amazing print formats are supported.
See the help for which command line switches to use.
Amazing Print output (`-o a`) uses ANSI color when stdout is a terminal and plain text when output is piped or
redirected. Pipe through `tee` if you want terminal-readable plain output while also saving or forwarding it.
If you are scripting against the CLI, prefer machine-readable output such as JSON (`-o j`)
instead of parsing human-formatted text. Structured output is simpler to consume and less likely
to change over time.
In _interactive_ mode, you can call the usual Ruby methods (`to_json`, `to_yaml`, etc.) instead.

### Timestamp Timezone

User-visible timestamps default to local time. The `--utc` option requires an explicit boolean value. To print
timestamps in UTC, pass `--utc true` or `-u true` before the command:

```bash
wifiwand --utc true info # true values: true, t, yes, y, +
wifiwand -u true log     # false values: false, f, no, n, -
```

To force local-time output when a default option enables UTC, pass `--utc false` or `-u false`.
Boolean values may also use inline forms such as `--utc=false`, `-ufalse`, `--verbose=true`, or `-vtrue`.

### Seeing the Underlying OS Commands and Output

If you would like to see the OS commands and their output,
you can do so by specifying `-v true` (for _verbose_) on the command line.
To disable verbose mode when a default option enables it, pass `--verbose false` or `-v false`.
Inline forms such as `--verbose=true` and `-vfalse` are also accepted.

On Ubuntu, when you connect with an inline password, wifiwand intentionally
passes that password to `nmcli` as a command-line argument. This means the
password can appear in verbose output and may be visible to local process
inspection tools such as `ps` while the command is running.

This behavior is intentional. wifiwand is designed primarily for individual
operators on machines they fully control, and showing the exact supplied
password is useful when diagnosing failed joins, stale saved credentials, and
quoting or escaping mistakes. Do not use inline passwords with wifiwand on
machines where other local users or local process inspection are not trusted.

### Interactive Shell Mode vs Command Line Mode

**Command Line Mode** (default): Execute single commands and exit
```bash
wifiwand info          # Run once, show output, exit
wifiwand connect MyNet # Connect and exit
```

**Interactive Shell Mode** (`shell` command): Start a persistent Ruby session
```bash
wifiwand shell         # Enter interactive mode
[1] pry(#<WifiWandView>)> info
[2] pry(#<WifiWandView>)> connect "MyNet"
[3] pry(#<WifiWandView>)> cycle; connect "MyNet"
```

The shell is useful when you want to:
* Issue multiple commands without restarting the program
* Combine commands and manipulate their output with Ruby code
* Use the data in formats not provided by the CLI
* Shell out to other programs (prefix with `.`)
* Work with the results interactively

If you `gem install` (or `sudo gem install` if necessary) the `pry-coolline` gem, than pry will use it
for its readline operations. This can resolve some readline issues and adds several readline enhancements.

### Using Variables in the Shell

#### Local Variable Shadowing

In Ruby, when both a method and a local variable have the same name,
the local variable will shadow (override) the method name. Therefore, local variables
may override this app's commands.  For example:

```
[1] pry(#<WifiWandView>)> x  # exit command, available as 'x' or 'xit'
$
$ wifiwand shell

[1] pry(#<WifiWand::CommandLineInterface>)> x = :foo  # override it with a local variable
:foo
[2] pry(#<WifiWand::CommandLineInterface>)> x  # 'x' no longer calls the exit method
:foo
[3] pry(#<WifiWand::CommandLineInterface>)> xit  # but the full method name still works
➜  ~ 
``` 

If you don't want to deal with this, you could use global variables, instance variables,
or constants, which will _not_ hide the methods:

```
[1] pry(#<WifiWand::CommandLineInterface>)> NETWORK_NAME = 123
123
[2] pry(#<WifiWand::CommandLineInterface>)> @network_name = 456
456
[3] pry(#<WifiWand::CommandLineInterface>)> $network_name = 789
789
[4] pry(#<WifiWand::CommandLineInterface>)> puts network_name, NETWORK_NAME, @network_name, $network_name
Superfast_5G
123
456
789
nil  # (return value of puts)
```

2) If you accidentally refer to a nonexistent variable or method name,
the result may be mysterious.  For example, if I were write the WiFi information
to a file, this would work:

```
[1] pry(#<WifiWandView>)> File.write('x', info)
=> 431
```

However, if I forget to quote the filename, the program exits:

```
[2] pry(#<WifiWandView>)> File.write(x, info)
➜  wifiwand git:(master) ✗  
```

What happened? `x` was assumed by Ruby to be a method name.
`method_missing` was called, and since `x` is the exit
command, the program exited.

Bottom line is, be careful to quote your strings, and you're probably better off using 
constants or instance variables if you want to create variables in your shell. 



### Examples

#### Single Command Invocations

```
wifiwand i            # prints out WiFi info
wifiwand a            # prints out names of available networks
wifiwand pr           # prints preferred networks
wifiwand cy           # cycles the WiFi off and on
wifiwand co a-network a-password # connects to a network requiring a password
wifiwand co a-network            # connects to a network _not_ requiring a password
wifiwand qr          # print ANSI QR to terminal
wifiwand qr wifi.png # generate PNG file: wifi.png
wifiwand qr wifi.svg # generate SVG file: wifi.svg
wifiwand qr - secret # print ANSI QR using an explicit password
wifiwand t internet_on && say "Internet connected" # Play audible message when Internet becomes connected
wifiwand s           # display status (WiFi, WiFi Network, DNS, Internet)
wifiwand log         # monitor WiFi status changes in real-time (to terminal)
wifiwand log --file  # log WiFi events to wifiwand-events.log
wifiwand log --file --stdout        # log to file AND display in terminal
wifiwand log --interval 1 --file    # check every 1 second instead of default 5
```

#### Interactive Shell Commands

The `pry` shell used by wifiwand outputs the last evaluated value in the terminal session.
The `amazing_print` gem is used to format that output nicely.
As with other shells, command return values can also be used in expressions, passed to methods,
saved in variables, etc. In this example, the value returned by the wifiwand command is saved
in the local variable `local_ip`.

```
[14] pry(#<WifiWand::CommandLineInterface>)> local_ip = info['ipv4_addresses'].grep(/192/).first
=> "192.168.110.251"
[15] pry(#<WifiWand::CommandLineInterface>)> puts "My IP address on the LAN is #{local_ip.inspect}"
My IP address on the LAN is "192.168.110.251"
```

By the way, if you want to suppress output altogether (e.g. if you are using the value in an
expression and don't need to see it displayed, you can simply append `;nil` to the expression
and `nil` will be the value output to the console. For example, the system may have hundreds
of preferred networks, so you might want to suppress their output:

```
[10] pry(#<WifiWand::CommandLineInterface>)> prs = pref_nets; nil
=> nil
```

### Using as a Library

The `wifiwand` gem can be used as a library in your own Ruby applications.
Use the OS-specific models directly. For most callers, the simplest entry point
is `WifiWand.create_model`, which returns the right model for the current host.

#### Basic Usage

First, add the gem to your Gemfile or install it system-wide. Then, require it
and create a model:

```ruby
require 'wifi_wand'

# Create the current OS model (WifiWand::Platforms::Mac::Model or
# WifiWand::Platforms::Ubuntu::Model)
model = WifiWand.create_model

# You can now call methods on the model directly
puts "WiFi is on: #{model.wifi_on?}"
puts "Connected to: #{model.connected_network_name}"

puts "\nAvailable Networks:"
puts model.available_network_names.map { |n| "  - #{n}" }
```

`available_network_names` reflects the SSIDs returned by the operating system scan, with wifiwand's
existing ordering and deduplication applied. The currently connected network may appear or may be absent,
depending on what the OS scan reports.

#### Passing Options

You can pass options when creating the model, such as `:verbose` to see
underlying OS commands or `:wifi_interface` to specify a network interface.

```ruby
require 'wifi_wand'

model = WifiWand.create_model(
  verbose: true,
  wifi_interface: 'en0'
)

puts model.wifi_info
```

`WifiWand.create_model` accepts a `Hash`.

#### Concrete Models

If you know the host OS up front, you can instantiate the concrete class
directly:

```ruby
require 'wifi_wand/platforms/mac/model'

model = WifiWand::Platforms::Mac::Model.create_model(verbose: true)
puts model.connected_network_name
```

```ruby
require 'wifi_wand/platforms/ubuntu/model'

model = WifiWand::Platforms::Ubuntu::Model.create_model(wifi_interface: 'wlp0s20f3')
puts model.connected_network_name
```

#### Available Methods

The model classes provide the library API for interacting with your Wi-Fi
interface. Key methods include:

*   `available_network_names`
*   `connect(ssid, password)`
*   `connected_network_name`
*   `connected_to?(ssid)`
*   `internet_connectivity_state` — returns `:reachable`, `:unreachable`, or `:indeterminate`
*   `captive_portal_login_required` — returns `:yes`, `:no`, or `:unknown`
*   `cycle_network`
*   `default_interface`
*   `disconnect`
*   `dns_working?`
*   `generate_qr_code(filespec = nil)`
*   `print_qr_code`
*   `render_qr_code(format: :ansi)`
*   `internet_tcp_connectivity?`
*   `ipv4_addresses`
*   `ipv6_addresses`
*   `mac_address`
*   `nameservers`
*   `os` — returns the current OS identifier as a symbol (`:mac`, `:ubuntu`)
*   `preferred_networks`
*   `random_mac_address`
*   `remove_preferred_networks(*ssids)`
*   `status_line_data`
*   `wifi_info`
*   `wifi_off`
*   `wifi_on`
*   `wifi_on?`

OS-specific methods remain available on the concrete models. For example,
`preferred_network_password` is available on `WifiWand::Platforms::Mac::Model` and
`WifiWand::Platforms::Ubuntu::Model`, but it is not part of the common cross-platform API.

Please refer to the YARD documentation for a complete list of methods and
their parameters.

**Migration: `connected_to_internet?` → `internet_connectivity_state`**

```ruby
# Old
model.connected_to_internet? == true

# New
model.internet_connectivity_state == :reachable
```

```ruby
case model.internet_connectivity_state
when :reachable
  puts 'Internet reachable'
when :unreachable
  puts 'Internet unreachable'
when :indeterminate
  puts 'Internet state unknown'
end
```

**More Examples**

(For brevity, semicolons are used here to put multiple commands on one line, 
but these commands could also each be specified on a line of its own.)

```
# Print out WiFi info:
> info

# Cycle (off/on) the network then connect to the specified network not requiring a password
> cycle; connect 'my-network'

# Cycle (off/on) the network, then connect to the same network not requiring a password
> @name = network_name; cycle; connect @name

# Cycle (off/on) the network then connect to the specified network using the specified password
> cycle; connect 'my-network', 'my-password'

> @i = i; "Interface: #{@i['interface']}, SSID: #{@i['network']}, IPv4 addresses: #{@i['ipv4_addresses'].join(', ')}."
Interface: wlp0s20f3, SSID: CafeBleu 5G, IPv4 addresses: 192.168.110.251.

> puts "There are #{pr.size} preferred networks."
There are 341 preferred networks.

# Delete all preferred networks whose names begin with "TOTTGUEST", the hard way:
> pr.grep(/^TOTTGUEST/).each { |n| forget(n) }

# Delete all preferred networks whose names begin with "TOTTGUEST", the easy way.
# 'forget' can take multiple network names, 
# but they must be specified as separate parameters; thus the '*'.
> forget(*pr.grep(/^TOTTGUEST/))

# Define a method to wait for the Internet connection to be active.
# (This functionality is included in the `till` command.)
# Call it, then output celebration message:
> def wait_for_internet; loop do; break if internet_connectivity_state == :reachable; sleep 0.1; end; end
> wait_for_internet; puts "Connected!"
Connected!

# Use the model's `till` method to simplify:
> till :internet_on, wait_interval_in_secs: 0.1
```


### Generate Wi‑Fi QR Codes

You can create QR codes for the currently connected network to share credentials quickly:

- Default terminal output: `wifiwand qr` prints an ANSI QR directly to the terminal
- File output: `wifiwand qr wifi.png`
- Alternate formats via filespec:
  - `.png` → PNG output (the default file format)
  - `.svg` → SVG output (uses `qrencode -t SVG`)
  - `.eps` → EPS output (uses `qrencode -t EPS`)
- Explicit password with terminal output: `wifiwand qr - secret-password`

Notes:
- Requires `qrencode` to be installed (macOS: `brew install qrencode`, Ubuntu: `sudo apt install qrencode`).
- If wifiwand cannot determine whether the current network is open, pass the optional password argument.
- When a target file already exists, wifiwand prompts before overwriting in interactive terminals; in
  non-interactive use, it errors instead.
- File output accepts no extension or one of `.png`, `.svg`, and `.eps`; other extensions are rejected to avoid
  writing one format under a misleading filename.
- For PDF, generate an SVG first and convert with a separate tool (e.g., `rsvg-convert`, `inkscape`, or
  ImageMagick's `magick`).
- In the interactive shell, type `qr` to display the QR code directly.
- Ruby code can get rendered QR data without printing or writing by calling `render_qr_code(format: :ansi)`.
  Supported render formats are `:ansi`, `:png`, `:svg`, and `:eps`.


### Public IP Information

The `info` command does not include public IP data. Use `wifiwand public_ip` or `wifiwand pi`
when you want the public IP address, country, or both.

wifiwand uses `https://api.country.is/` when the country is requested, including the default
`both` selector, and `https://api.ipify.org` when only the public IP address is requested.

If the provider request fails or returns malformed data, the command raises a public IP lookup error.
In that case, the web site 'https://www.iplocation.net/' is recommended, and `wifiwand ro ipl` on
the command line or `ro 'ipl'` in the shell will open that page in your browser for you.


### Password Lookup Oddity

You may find it odd (I did, anyway) that on macOS even if you issue the password command
(`wifiwand password a-network-name`) using sudo, you will still be prompted
with a graphical dialog for both a user id and password. This is no doubt
for better security, but it's unfortunate in that it makes it impossible to fully automate this task.

In particular, it would be nice for the `cycle` command to be able to fetch the current network's
password, cycle the network, and then reconnect to the original network with it after turning the network on.
However, since fetching the password without user intervention is not possible, this cannot be automated.

If you don't mind storing the network password in plain text somewhere, then you could easily
automate it (e.g. `wifiwand cycle && wifiwand connect a-network a-password`). Also, you might find it handy
to create a script for your most commonly used networks containing something like this:

```
wifiwand  connect  my-usual-network  its-password
```

### Airport Utility Deprecation (April 2024)

Starting in macOS version 14.4, the `airport` utility on which some of this project's
functionality relies has been disabled and will presumably eventually be removed.

#### Swift/CoreWLAN Wrappers

To maintain functionality after airport deprecation and macOS permission changes, wifiwand now uses two
Swift/CoreWLAN runtime paths on macOS:

* **Compiled helper application for read/query operations** - On macOS Sonoma (14.0) and later, the signed
  `wifiwand-helper.app` helper application handles permission-sensitive operations such as reading current
  network details and scanning nearby networks.
* **Direct Swift source for connect/disconnect** - `WifiNetworkConnector.swift` and
  `WifiNetworkDisconnector.swift` still handle connect/disconnect, with automatic fallback to
  `networksetup` or `ifconfig` when needed.

The helper application path exists because modern macOS read/query operations increasingly depend on CoreWLAN
plus a stable app identity for Location Services behavior. The direct Swift-source path remains in place
because the existing connect/disconnect flow still works well with its fallbacks. Consolidating these paths
is a later architecture topic, not part of the current cleanup.

The direct Swift scripts are **optional dependencies**. If Swift or CoreWLAN are not available (for example,
Xcode Command Line Tools are not installed), wifiwand automatically falls back to traditional command-line
utilities (`networksetup`, `ifconfig`) with slightly reduced functionality for connect/disconnect.

To install Swift and CoreWLAN support:
```bash
xcode-select --install
```

The following tasks now rely on a mix of helper-application-backed reads and
traditional macOS utilities:
* determining whether or not WiFi is on
* reading the name of the currently connected network
* listing names of available networks

The only remaining issue is that we were getting some extended information from airport for each available
network. This extended information has now been removed in version 2.17.0.

In addition, the extended information about the available networks (`ls_avail_nets`) has been removed in
version 2.17.0.


### macOS Helper Cleanup (macOS Sonoma+)

On macOS Sonoma (14.0) and later, wifiwand installs a native macOS helper application to
`~/Library/Application Support/WifiWand/<version>/` to provide unredacted WiFi information. Each gem version
creates its own helper application directory to support running multiple gem versions simultaneously.

Over time, old helper application versions may accumulate as you upgrade. Each helper application is
~100-200KB, so this is rarely a concern, but you can clean them up if desired.

**List installed helper application versions:**
```bash
ls -la ~/Library/Application\ Support/WifiWand/
```

**Remove all helpers** (they will be reinstalled automatically when needed):
```bash
rm -rf ~/Library/Application\ Support/WifiWand/
```

**Remove specific old versions only:**
```bash
# Example: keep 3.0.0-alpha.1, remove all others
cd ~/Library/Application\ Support/WifiWand/
ls | grep -v "3.0.0-alpha.1" | xargs rm -rf
```

The helper application will be automatically reinstalled the next time you run a wifiwand command that
requires it. To remove the helper for the currently installed wifiwand version, run:

```bash
wifiwand-macos-setup --remove
```

If you want to refresh the currently installed helper application immediately, run:

```bash
wifiwand-macos-setup --reinstall
```


### License

Apache 2 License (see LICENSE.txt)

### Logo

Logo designed and generously contributed by Anhar Ismail (Github:
[@anharismail](https://github.com/anharismail), Twitter: [@aizenanhar](https://twitter.com/aizenanhar)).


### Contact Me

I am available for consulting, development, tutoring, training, troubleshooting, etc.
Here is my contact information:

* GMail, Github, LinkedIn, X, : _keithrbennett_
* Website: [Bennett Business Solutions, Inc.](https://www.bbs-software.com)
