![logo](logo/wifiwand-logo-horizontal-color.png)

# wifi-wand

To install this software, run:

`gem install wifi-wand`

or, you may need to precede that command with `sudo`:

`sudo gem install wifi-wand`

The `wifi-wand` gem enables the query and management 
of WiFi configuration, environment, and behavior, on Mac and Ubuntu systems.
Internally, it uses OS-specific command line utilities to interact with the
underlying operating system -- for example, `networksetup`, `system_profiler`,
and `ipconfig` on macOS, and `nmcli`, `iw`, and `ip` on Ubuntu Linux.
However, the code encapsulates the OS-specific logic in model subclasses with identical
method names and argument lists, so that they present a unified interface for use in:

* command line invocation (e.g. `wifi-wand co my-network my-password` to connect to a network)
* interactive shell (REPL) sessions where the wifi-wand methods are effectively DSL commands (`wifi-wand -s` to run in interactive mode)
* other Ruby applications as a gem (library) (`require wifi-wand`)

### Usage

Available commands can be seen by using the `-h` (or `--help`) option. Here is its
output at the time of this writing:

```

Command Line Switches:                    [wifi-wand version 2.20.0 at https://github.com/keithrbennett/wifiwand]

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
ro[pen]                   - open resource ('cap' (Portal Logins), 'ipl' (IP Location), 'ipw' (What is My IP), 'libre' (LibreSpeed), 'spe' (Speed Test), 'this' (wifi-wand home page))
t[ill]                    - returns when the desired Internet connection state is true. Options:
                            1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                            2) wait interval between tests, in seconds (optional, defaults to 0.5 seconds)
w[ifi_on]                 - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`.
```

### Pretty Output

The `awesome_print` gem is used for formatting output nicely in both non-interactive and interactive (shell) modes.

### JSON, YAML, and Other Output Formats

You can specify that output in _noninteractive_ mode be in a certain format.
Currently, JSON, "Pretty" JSON, YAML, inspect, and puts formats are supported.
See the help for which command line switches to use.


### Seeing the Underlying OS Commands and Output

If you would like to see the OS commands and their output, 
you can do so by specifying "-v" (for _verbose_) on the command line.

You may notice that some commands are executed more than once. This is to simplify the application logic
and eliminate the need for the complexity of balancing the speed that a cache offers and the risk
of stale data.


### Troubleshooting

If you try to run the shell, the script will require the `pry` gem, so that will need to be installed.
`pry` in turn requires access to a `readline` library. If you encounter an error relating to finding a
`readline` library, this can probably be fixed by installing the `pry-coolline` gem: `gem install pry-coolline`.
If you are using the Ruby packaged with Mac OS, or for some other reason require root access to install
gems, you will need to precede those commands with `sudo`:

```
sudo gem install pry
sudo gem install pry-coolline
```


### Using the Shell

The shell, invoked with the `-s` switch on the command line, provides an interactive
session. It can be useful when:

* you want to issue multiple commands
* you want to combine commands
* you want the data in a format not provided by this application
* you want to incorporate these commands into other Ruby code interactively
* you want to combine the results of commands with other OS commands 
  (you can shell out to run other command line programs by preceding the command with a period (`.`))   .

### Using Variables in the Shell

There are a couple of things (that may be surprising) to keep in mind
when using the shell. They relate to the fact that local variables
and method calls use the same notation in Ruby (since use of parentheses
in a method call is optional):

1) In Ruby, when both a method and a local variable have the same name,
the local variable will override the method name. Therefore, local variables
may override this app's commands.  For example:

```
[1] pry(#<WifiWandView>)> n  # network_name command
=> ".@ AIS SUPER WiFi"
[2] pry(#<WifiWandView>)> n = 123  # override it with a local variable
=> 123
[3] pry(#<WifiWandView>)> n  # 'n' no longer calls the method
=> 123
[4] pry(#<WifiWandView>)> ne  # but any other name that `network_name starts with will still call the method
=> ".@ AIS SUPER WiFi"
[5] pry(#<WifiWandView>)> network_name
=> ".@ AIS SUPER WiFi"
[6] pry(#<WifiWandView>)> ne_xzy123
"ne_xyz123" is not a valid command or option. If you intend for this to be a string literal, use quotes.
``` 

If you don't want to deal with this, you could use global variables, instance variables,
or constants, which will _not_ hide the methods:

```
[7] pry(#<WifiWandView>)> N = 123
[8] pry(#<WifiWandView>)> @n = 456
[9] pry(#<WifiWandView>)> $n = 789
[10] pry(#<WifiWandView>)> puts n, N, @n, $n
.@ AIS SUPER WiFi
123
456
789
=> nil
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
wifi-wand i            # prints out wifi info
wifi-wand a            # prints out names of available networks
wifi-wand pr           # prints preferred networks
wifi-wand cy           # cycles the wifi off and on
wifi-wand co a-network a-password # connects to a network requiring a password
wifi-wand co a-network            # connects to a network _not_ requiring a password
wifi-wand t on && say "Internet connected" # Play audible message when Internet becomes connected
```

#### Interactive Shell Commands

The `pry` shell used by wifi_wand outputs the last evaluated value in the terminal session.
The `awesome_print` gem is used to format that output nicely.
In addition to outputting the value to the terminal, the command's value can be used in an expression.
For example:

```
[14] pry(#<WifiWand::CommandLineInterface>)> local_ip = info['ip_address'].split("\n").grep(/192/).first
=> "192.168.110.251"
[15] pry(#<WifiWand::CommandLineInterface>)> puts "My IP address on the LAN is #{local_ip.inspect}"
My IP address on the LAN is "192.168.110.251"
```

If you want to suppress output altogether (e.g. if you are using the value in an
expression and don't need to see it displayed,
you can simply append `;nil` to the expression
and `nil` will be the value output to the console. For example:

```
[10] pry(#<WifiWand::CommandLineInterface>)> available_networks = avail_nets; nil
=> nil
```

#### Using the Models Without the Command Line Interface

The code has been structured so that you can call the models
from your own Ruby code, bypassing the command line interface.
Here is an example of how to do that:

```ruby
require 'wifi-wand'
model = WifiWand::OperatingSystems.create_model_for_current_os
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


### Dependent Gems

Currently, dependent gems are installed automatically when this gem is installed.
However, the program _will_ use other gems as follows:

* `pry`, when the interactive shell is requested with the `-s` option
* `awesome_print`, to provide nicely formatted output, to more nicely format output in non-interactive mode

and as long as they are comfortable with the less pretty output.


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

You may find it odd (I did, anyway) that even if you issue the password command 
(`mac_wifi password a-network-name`) using sudo, you will still be prompted 
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

Starting in Mac OS version 14.4, the `airport` utility on which some of this project's
functionality relies has been disabled and will presumably eventually be removed.

The following tasks were restored by using Swift scripts:
* listing names of all available networks
* disconnecting from a network (with the added benefit that sudo access is no longer required)

The following tasks were restored by using `networksetup`:
* determining whether or not wifi is on
* the name of the currently connected network

The only remaining issue is that we were getting some extended information from airport for each available network. This extended information has now been removed in version 2.17.0.

In addition, the extended information about the available networks (`ls_avail_nets`) has been removed in version 2.17.0.


### License

Apache 2 License (see LICENSE.txt)

### Logo

Logo designed and generously contributed by Anhar Ismail (Github: [@anharismail](https://github.com/anharismail), Twitter: [@aizenanhar](https://twitter.com/aizenanhar)).


### Shameless Ad

I am available for consulting, development, tutoring, training, troubleshooting, etc.

You can contact me via GMail, Twitter, Github, and LinkedIn, as _keithrbennett_.
