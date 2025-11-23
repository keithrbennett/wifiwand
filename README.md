![logo](logo/wifiwand-logo-horizontal-color.png)

# wifi-wand

### Installation

**Requirements:** Ruby >= 3.2.0

To install this software, run:

`gem install wifi-wand`

or, you may need to precede that command with `sudo` to install it system-wide:

`sudo gem install wifi-wand`

**Note for macOS users:** macOS ships with Ruby 2.6. If you get an installation error about Ruby version or the `traces` gem, install a modern Ruby. The simplest way is with Homebrew:

```bash
brew install ruby

# Add to ~/.zshrc or ~/.bash_profile:
# Apple Silicon Macs:
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

# Intel Macs:
export PATH="/usr/local/opt/ruby/bin:$PATH"
```

<details>
<summary><strong>Unsupported workaround for Ruby < 3.2</strong></summary>

If you must use an older Ruby version (not supported), you can try modifying `wifi-wand.gemspec` before building:

```ruby
spec.required_ruby_version = ">= 2.7.0"    # change from ">= 3.2.0"
spec.add_dependency('async', '~> 1.30')    # change from '~> 2.0'
```

Then build and install:
```bash
gem build wifi-wand.gemspec
gem install wifi-wand-*.gem
```

Note: This configuration is not tested or supported. Use at your own risk.
</details>

Optional dependency for QR codes:

- To use the `wifi-wand qr` command for generating Wi‑Fi QR codes, install `qrencode`.
  - macOS: `brew install qrencode`
  - Ubuntu: `sudo apt install qrencode`

---

### ⚠️ Important for macOS Users (10.15+)

**After installation, run the one-time setup script:**

```bash
wifi-wand-macos-setup
```

This grants location permission needed for WiFi network access. Without it, network names may appear as `<hidden>` or `<redacted>`. See the [macOS Setup Guide](docs/MACOS_SETUP.md) for details.

---

### Description

The `wifi-wand` gem enables the query and management 
of WiFi configuration, environment, and behavior, on Mac and Ubuntu systems.
Internally, it uses OS-specific command line utilities to interact with the
underlying operating system -- for example, `networksetup`, `system_profiler`,
and `ipconfig` on macOS, and `nmcli`, `iw`, and `ip` on Ubuntu Linux.
However, the code encapsulates the OS-specific logic in model subclasses with identical
method names and argument lists, so that they present a unified interface for use in:

* command line invocation (e.g. `wifi-wand co my-network my-password` to connect to a network)
* interactive shell (REPL) sessions where the WiFi-wand methods are effectively DSL commands (`wifi-wand shell` to run in interactive mode)
* other Ruby applications as a gem (library) (`require 'wifi-wand'`)

### ⚠️ Breaking Change: Interactive Shell

The interactive shell is now a dedicated subcommand: run it with `wifi-wand shell`.
The legacy `-s/--shell` option has been removed—update any scripts or aliases that
still rely on the flag before upgrading.

### Quick Start

```bash
# Display networking status (e.g.: WiFi: ON | Network: "my_network" | TCP: YES | DNS: YES | Internet: YES)
wifi-wand s

# Display WiFi on/off status
wifi-wand w

# See available WiFi networks
wifi-wand a

# Connect to a WiFi network with password
wifi-wand co MyNetwork password

# Connect to a WiFi network without password (if no password required or network is saved/preferred
wifi-wand co MyNetwork

# Force an open-network attempt even if a saved password exists
wifi-wand co MyNetwork ''

# Display detailed networking information
wifi-wand i

# Start interactive shell
wifi-wand shell

# Display underlying OS calls and their output
wifi-wand -v ...
```

### Documentation

For detailed information about specific features:

- **[Event Logging (`log` command)](docs/LOGGING.md)** - Continuously monitor WiFi state changes, log events over time, and detect network issues
- **[Status Command](docs/STATUS_COMMAND.md)** - Understand WiFi and connectivity status display
- **[Info Command](docs/INFO_COMMAND.md)** - Get detailed network configuration and status information
- **[Connectivity Checking (`ci` command)](docs/CONNECTIVITY_CHECKING.md)** - Check internet availability in scripts and automation
- **[Testing Guide](docs/TESTING.md)** - Running tests, coverage reports, and test categories
- **[DNS Configuration Guide](docs/DNS_Configuration_Guide.md)** - Managing nameservers and DNS settings
- **[Environment Variables Reference](docs/ENVIRONMENT_VARIABLES.md)** - Configuration via environment variables (including the `WIFIWAND_OPTS` default-options helper)

### Usage

Available commands can be seen by using the `-h` (or `--help`) option:

```
Command Line Switches     [wifi-wand version 3.0.0-alpha.1 at https://github.com/keithrbennett/wifiwand]
---------------------
-h, --help                - show this help message
-o, --output_format {i,j,k,p,y}
                          - when not in shell mode, outputs data in the following formats: inspect, JSON, pretty JSON, puts, YAML
-p, --wifi-interface interface_name
                          - specify WiFi interface name (overrides auto-detection)
-v, --[no-]verbose        - verbose mode (prints OS commands and their outputs)
                            To disable: use --no-verbose or --no-v (short form negation like -v- is not supported)

Subcommands
-----------
shell                     - start interactive shell (interactive pry REPL session)

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
                                     --stdout (keep stdout when other destinations are requested), --hook PATH (execute hook script)
                            Logs events: WiFi on/off, network connect/disconnect, internet on/off
                            Ctrl+C to stop (see docs/LOGGING.md for details)
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
ro[pen]                   - open web resources: 'cap' (Portal Logins), 'ipl' (IP Location), 'ipw' (What is My IP), 'libre' (LibreSpeed), 'spe' (Speed Test), 'this' (wifi-wand home page)
s[tatus]                  - status line (WiFi, Network, TCP, DNS, Internet) with real-time connectivity checks
                            (see docs/STATUS_COMMAND.md for details on connectivity detection)
t[ill]                    - wait until Internet connection reaches desired state:
                            'on'/:on (connected), 'off'/:off (disconnected), 'conn'/:conn (connected), 'disc'/:disc (disconnected)
                            Optional: wait interval between checks in seconds (default: 0.5)
w[ifi_on]                 - is the WiFi on?
x[it]                     - exits this program (interactive shell mode only) (same as 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`, e.g. `%ls`.
  * To display the QR code in the shell, pass the string returned by `qr :-` to `puts`. Ex: `puts(qr :-)`
```

### Pretty Output

The `awesome_print` gem is used for formatting output nicely in both non-interactive and interactive (shell) modes.

### JSON, YAML, and Other Output Formats

You can specify that output in _noninteractive_ mode be in a certain format.
Currently, JSON, "Pretty" JSON, YAML, inspect, and puts formats are supported.
See the help for which command line switches to use.
In _interactive_ mode, you can call the usual Ruby methods (`to_json`, `to_yaml`, etc.) instead.


### Seeing the Underlying OS Commands and Output

If you would like to see the OS commands and their output,
you can do so by specifying "-v" (for _verbose_) on the command line.
To disable verbose mode, use `--no-verbose` or `--no-v`
(Ruby's OptionParser does not support short-form negations like `-v-`).

### Interactive Shell Mode vs Command Line Mode

**Command Line Mode** (default): Execute single commands and exit
```bash
wifi-wand info          # Run once, show output, exit
wifi-wand connect MyNet # Connect and exit
```

**Interactive Shell Mode** (`shell` subcommand): Start a persistent Ruby session
```bash
wifi-wand shell         # Enter interactive mode
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
[1] pry(#<WifiWandView>)> x  # exit command, can be called as 'x', 'xi', or 'xit'
$
$ wifi-wand shell

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
➜  wifi-wand git:(master) ✗  
```

What happened? `x` was assumed by Ruby to be a method name.
`method_missing` was called, and since `x` is the exit
command, the program exited.

Bottom line is, be careful to quote your strings, and you're probably better off using 
constants or instance variables if you want to create variables in your shell. 



### Examples

#### Single Command Invocations

```
wifi-wand i            # prints out WiFi info
wifi-wand a            # prints out names of available networks
wifi-wand pr           # prints preferred networks
wifi-wand cy           # cycles the WiFi off and on
wifi-wand co a-network a-password # connects to a network requiring a password
wifi-wand co a-network            # connects to a network _not_ requiring a password
wifi-wand qr          # generate PNG file: <SSID>-qr-code.png
wifi-wand qr wifi.svg # generate SVG file: wifi.svg
wifi-wand qr -        # print ANSI QR to terminal
wifi-wand t on && say "Internet connected" # Play audible message when Internet becomes connected
wifi-wand s           # display status (WiFi, Network, TCP, DNS, Internet)
wifi-wand log         # monitor WiFi status changes in real-time (to terminal)
wifi-wand log --file  # log WiFi events to wifiwand-events.log
wifi-wand log --file --stdout        # log to file AND display in terminal
wifi-wand log --interval 1 --file    # check every 1 second instead of default 5
```

#### Interactive Shell Commands

The `pry` shell used by wifi_wand outputs the last evaluated value in the terminal session.
The `awesome_print` gem is used to format that output nicely.
As with other shells, command return values can also be used in expressions, passed to methods,
saved in variables, etc. In this example, the value returned by the WiFi-wand command is saved
in the local variable `local_ip`.

```
[14] pry(#<WifiWand::CommandLineInterface>)> local_ip = info['ip_address'].split("\n").grep(/192/).first
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

The `wifi-wand` gem can be used as a library in your own Ruby applications. The primary entry point for the library is the `WifiWand::Client` class.

#### Basic Usage

First, add the gem to your Gemfile or install it system-wide. Then, require it and create a new client:

```ruby
require 'wifi-wand'

# Create a new client instance
client = WifiWand::Client.new

# You can now call methods on the client
puts "WiFi is on: #{client.wifi_on?}"
puts "Connected to: #{client.connected_network_name}"

puts "\nAvailable Networks:"
puts client.available_network_names.map { |n| "  - #{n}" }
```

#### Passing Options

You can pass options to the client during initialization, such as `:verbose` to see underlying OS commands or `:wifi_interface` to specify a network interface.

```ruby
require 'wifi-wand'
require 'ostruct'

options = OpenStruct.new(verbose: true, wifi_interface: 'en0')
client = WifiWand::Client.new(options)

puts client.wifi_info
```

#### Available Methods

The `Client` object provides a comprehensive API for interacting with your Wi-Fi interface. All public methods on the underlying OS-specific models are delegated to the client. Key methods include:

*   `available_network_names`
*   `connect(ssid, password)`
*   `connected_network_name`
*   `connected_to?(ssid)`
*   `connected_to_internet?`
*   `cycle_network`
*   `default_interface`
*   `disconnect`
*   `dns_working?`
*   `generate_qr_code(filespec: nil)`
*   `internet_tcp_connectivity?`
*   `ip_address`
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

Please refer to the YARD documentation for a complete list of methods and their parameters.


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

> @i = i; "Interface: #{@i['interface']}, SSID: #{@i['network']}, IP address: #{@i['ip_address']}."
Interface: wlp0s20f3, SSID: CafeBleu 5G, IP address: 192.168.110.251.

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
> def wait_for_internet; loop do; break if ci; sleep 0.1; end; end
> wait_for_internet; puts "Connected!"
Connected!

# Use the model's `till` method to simplify:
> till :conn, 0.1
```


### Generate Wi‑Fi QR Codes

You can create QR codes for the currently connected network to share credentials quickly:

- Default file output (PNG): `wifi-wand qr` → `<SSID>-qr-code.png`
- Custom filespec: `wifi-wand qr wifi.png`
- Alternate formats via filespec:
  - `.svg` → SVG output (uses `qrencode -t SVG`)
  - `.eps` → EPS output (uses `qrencode -t EPS`)
- Text (stdout): `wifi-wand qr -` prints an ANSI QR directly to the terminal

Notes:
- Requires `qrencode` to be installed (macOS: `brew install qrencode`, Ubuntu: `sudo apt install qrencode`).
- When a target file already exists, wifi-wand prompts before overwriting in interactive terminals; in non-interactive use, it errors instead.
- For PDF, generate an SVG first and convert with a separate tool (e.g., `rsvg-convert`, `inkscape`, or ImageMagick's `magick`).
- **Interactive shell QR display**: When using `qr '-'` in the interactive shell, wrap the result with `puts` (e.g., `puts qr('-')`) to properly render the ANSI characters. Without `puts`, pry calls `inspect` on the string, which escapes the ANSI codes and prevents the QR code from displaying correctly.


### Public IP Information

The information hash will normally include information about the public IP address.
However, the command that provides this information, `curl -s ipinfo.io`, will sometimes
return this:

`Rate limit exceeded. Subscribe to a paid plan to increase your usage limits` 

If this happens, the public IP information will be silently omitted from the
information hash. In this case, the web site 'https://www.iplocation.net/' is
recommended, and `wifi-wand ro ipl` on the command line or `ro 'ipl'` in the shell will
open that page in your browser for you.


### Password Lookup Oddity

You may find it odd (I did, anyway) that on macOS even if you issue the password command 
(`wifi-wand password a-network-name`) using sudo, you will still be prompted 
with a graphical dialog for both a user id and password. This is no doubt
for better security, but it's unfortunate in that it makes it impossible to fully automate this task.

In particular, it would be nice for the `cycle` command to be able to fetch the current network's
password, cycle the network, and then reconnect to the original network with it after turning the network on.
However, since fetching the password without user intervention is not possible, this cannot be automated.

If you don't mind storing the network password in plain text somewhere, then you could easily
automate it (e.g. `wifi-wand cycle && wifi-wand connect a-network a-password`). Also, you might find it handy
to create a script for your most commonly used networks containing something like this:

```
wifi-wand  connect  my-usual-network  its-password
```

### Airport Utility Deprecation (April 2024)

Starting in macOS version 14.4, the `airport` utility on which some of this project's
functionality relies has been disabled and will presumably eventually be removed.

#### Swift/CoreWLAN Wrappers

To maintain functionality after airport deprecation, wifi-wand now uses Swift scripts with the CoreWLAN framework for several operations:

* **Connecting to networks** - Uses `WifiNetworkConnector.swift` (preferred method, with automatic fallback to `networksetup`)
* **Disconnecting from networks** - Uses `WifiNetworkDisconnector.swift` (with the added benefit that sudo access is no longer required, falls back to `ifconfig`)

These Swift wrappers are **optional dependencies**. If Swift or CoreWLAN are not available (e.g., Xcode Command Line Tools not installed), wifi-wand automatically falls back to traditional command-line utilities (`networksetup`, `ifconfig`) with slightly reduced functionality.

To install Swift and CoreWLAN support:
```bash
xcode-select --install
```

The following tasks were restored by using `networksetup` and `system_profiler`:
* determining whether or not WiFi is on
* the name of the currently connected network
* listing names of all available networks

The only remaining issue is that we were getting some extended information from airport for each available network. This extended information has now been removed in version 2.17.0.

In addition, the extended information about the available networks (`ls_avail_nets`) has been removed in version 2.17.0.


### macOS Helper Cleanup (macOS Sonoma+)

On macOS Sonoma (14.0) and later, wifi-wand installs a native helper app to `~/Library/Application Support/WifiWand/<version>/` to provide unredacted WiFi information. Each gem version creates its own helper directory to support running multiple gem versions simultaneously.

Over time, old helper versions may accumulate as you upgrade. Each helper is ~100-200KB, so this is rarely a concern, but you can clean them up if desired.

**List installed helper versions:**
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

The helper will be automatically reinstalled the next time you run a wifi-wand command that requires it.


### License

Apache 2 License (see LICENSE.txt)

### Logo

Logo designed and generously contributed by Anhar Ismail (Github: [@anharismail](https://github.com/anharismail), Twitter: [@aizenanhar](https://twitter.com/aizenanhar)).


### Contact Me

I am available for consulting, development, tutoring, training, troubleshooting, etc.
Here is my contact information:

* GMail, Github, LinkedIn, X: _keithrbennett_
* Website: [Bennett Business Solutions, Inc.](https://www.bbs-software.com)
