![logo](logo/wifiwand-logo-horizontal-color.png)

# wifi-wand

### Installation

To install this software, run:

`gem install wifi-wand`

or, you may need to precede that command with `sudo` to install it system-wide:

`sudo gem install wifi-wand`

Optional dependency for QR codes:

- To use the `wifi-wand qr` command for generating Wi‑Fi QR codes, install `qrencode`.
  - macOS: `brew install qrencode`
  - Ubuntu: `sudo apt install qrencode`

### Description

The `wifi-wand` gem enables the query and management 
of WiFi configuration, environment, and behavior, on Mac and Ubuntu systems.
Internally, it uses OS-specific command line utilities to interact with the
underlying operating system -- for example, `networksetup`, `system_profiler`,
and `ipconfig` on macOS, and `nmcli`, `iw`, and `ip` on Ubuntu Linux.
However, the code encapsulates the OS-specific logic in model subclasses with identical
method names and argument lists, so that they present a unified interface for use in:

* command line invocation (e.g. `wifi-wand co my-network my-password` to connect to a network)
* interactive shell (REPL) sessions where the WiFi-wand methods are effectively DSL commands (`wifi-wand -s` to run in interactive mode)
* other Ruby applications as a gem (library) (`require wifi-wand`)

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

# Display detailed networking information
wifi-wand i

# Start interactive shell
wifi-wand -s

# Display underlying OS calls and their output
wifi-wand -v ...
```

### Usage

Available commands can be seen by using the `-h` (or `--help`) option:

```
Command Line Switches     [wifi-wand version 3.0.0-alpha.1 at https://github.com/keithrbennett/wifiwand]
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
qr [filespec|'-']         - generate a Wi‑Fi QR code; default PNG file <SSID>-qr-code.png; '-' prints ANSI QR to stdout; '.svg'/' .eps' use those formats
ro[pen]                   - open web resources: 'cap' (Portal Logins), 'ipl' (IP Location), 'ipw' (What is My IP), 'libre' (LibreSpeed), 'spe' (Speed Test), 'this' (wifi-wand home page)
s[tatus]                  - status line (WiFi, Network, TCP, DNS, Internet)
t[ill]                    - wait until Internet connection reaches desired state:
                            'on'/:on (connected), 'off'/:off (disconnected), 'conn'/:conn (connected), 'disc'/:disc (disconnected)
                            Optional: wait interval between checks in seconds (default: 0.5)
w[ifi_on]                 - is the WiFi on?
x[it]                     - exits this program (interactive shell mode only) (same as 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`, e.g. `%ls`.
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

### Interactive Shell Mode vs Command Line Mode

**Command Line Mode** (default): Execute single commands and exit
```bash
wifi-wand info          # Run once, show output, exit
wifi-wand connect MyNet # Connect and exit
```

**Interactive Shell Mode** (`-s` flag): Start a persistent Ruby session
```bash
wifi-wand -s            # Enter interactive mode
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
$ wifi-wand -s

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
```

#### Interactive Shell Commands

The `pry` shell used by wifi_wand outputs the last evaluated value in the terminal session.
The `awesome_print` gem is used to format that output nicely.
As with other REPL's, command return values can also be used in expressions, passed to methods,
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

#### Using the Models Without the Command Line Interface

The code has been structured so that you can call the models from your own Ruby code,
bypassing the command line interface. Use the convenience factory `WifiWand.create_model`:

```ruby
require 'wifi-wand'
model = WifiWand.create_model
puts model.available_network_names.to_yaml # etc...
```

Or for a specific OS:

```ruby
require 'wifi-wand'
model = WifiWand::MacOsModel.new  # For macOS
# or
model = WifiWand::UbuntuModel.new  # For Ubuntu
puts model.available_network_names.to_yaml # etc...
```

You can also pass options to `create_model` (e.g., to enable verbose mode or set a specific interface):

```ruby
require 'wifi-wand'
require 'ostruct'

options = OpenStruct.new(verbose: true, wifi_interface: 'en0')
model = WifiWand.create_model(options)
puts model.wifi_info
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
- For PDF, generate an SVG first and convert with a separate tool (e.g., `rsvg-convert`, `inkscape`, or ImageMagick’s `magick`).


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

The following tasks were restored by using Swift scripts:
* listing names of all available networks
* disconnecting from a network (with the added benefit that sudo access is no longer required)

The following tasks were restored by using `networksetup`:
* determining whether or not WiFi is on
* the name of the currently connected network

The only remaining issue is that we were getting some extended information from airport for each available network. This extended information has now been removed in version 2.17.0.

In addition, the extended information about the available networks (`ls_avail_nets`) has been removed in version 2.17.0.


### License

Apache 2 License (see LICENSE.txt)

### Logo

Logo designed and generously contributed by Anhar Ismail (Github: [@anharismail](https://github.com/anharismail), Twitter: [@aizenanhar](https://twitter.com/aizenanhar)).


### Contact Me

I am available for consulting, development, tutoring, training, troubleshooting, etc.
Here is my contact information:

* GMail, Github, LinkedIn, X, : _keithrbennett_
* Website: [Bennett Business Solutions, Inc.](https://www.bbs-software.com)
