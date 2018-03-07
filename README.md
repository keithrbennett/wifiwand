# wifi-wand

To install this software, run:

`gem install wifi-wand`

or, you may need to precede that command with `sudo`:

`sudo gem install wifi-wand`

The `wifi-wand` gem enables the query and management 
of wifi configuration and environment on a Mac.
The code encapsulates the Mac OS specific logic in a minimal class 
to more easily add support for other operating systems,
but as of now, only Mac OS is supported. (Feel free to add an OS!)

It can be run in single-command or interactive mode. 
Interactive mode uses the [pry](https://github.com/pry/pry) gem,
providing an interface familiar to Rubyists and other 
[REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop) users.


### Usage

Available commands can be seen by using the `h` (or `help`) option. Here is its
output at the time of this writing:

```
$ wifi-wand -h

Command Line Switches:                    [wifi-wand version 2.6.0]

-o {i,j,k,p,y}            - outputs data in inspect, JSON, pretty JSON, puts, or YAML format when not in shell mode
-p wifi_port_name         - override automatic detection of port name with this name
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:

a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
cy[cle]                   - turns wifi off, then on, preserving network selection
d[isconnect]              - disconnects from current network, does not turn off wifi
h[elp]                    - prints this help
i[nfo]                    - a hash of wifi-related information
l[s_avail_nets]           - details about available networks
na[meservers]             - nameservers: 'show' or no arg to show, 'clear' to clear, or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
ne[twork_name]            - name (SSID) of currently connected network
on                        - turns wifi on
of[f]                     - turns wifi off
pa[ssword] network-name   - password for preferred network-name
pr[ef_nets]               - preferred (not necessarily available) networks
q[uit]                    - exits this program (interactive shell mode only) (see also 'x')
r[m_pref_nets] network-name - removes network-name from the preferred networks list
                          (can provide multiple names separated by spaces)
ro[pen]                   - open resource ('ipc' (IP Chicken), 'ipw' (What is My IP), 'spe' (Speed Test), 'this' (wifi-wand Home Page))
t[ill]                    - returns when the desired Internet connection state is true. Options:
                          1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                          2) wait interval, in seconds (optional, defaults to 0.5 seconds)
w[ifion]                  - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
  * use quotes for string parameters such as method names.
  * for pry commands, use prefix `%`.
```

Internally, it uses several Mac command line utilities. This is not ideal,
I would have preferred OS system calls, but the current approach enabled me to develop
this script quickly and simply.


### Pretty Output

For nicely formatted output of the `info` command in non-interactive mode,
the `awesome_print` gem is used if it is installed;
otherwise, the somewhat less awesome pretty print (`pp`) is used.  Therefore,
installation of the `awesome_print` gem is recommended. 
This is accomplished by the following command:

`gem install awesome_print`

You may need to precede this command with `sudo `, especially if you are using the 
version of Ruby that comes packaged with MacOS.


### JSON, YAML, and Other Output Formats

You can specify that output in _noninteractive_ mode be in a certain format.
Currently, JSON, YAML, inspect, and puts formats are supported.
See the help for which command line switches to use.


### Seeing the Underlying OS Commands and Output

If you would like to see the Mac OS commands and their output, 
you can do so by specifying "-v" (for _verbose) on the command line.

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


### Using It in Scripts

Sometimes calling `wifi-wand` from a script is handy. I have this script that
connects to a commonly used wifi network, and then speaks a message when it's done:

```
wifi-wand connect my_network_name my_password  && \
wifi-wand till conn && \
say -v Kyoko "Connected to my network."
```

(The Mac OS `say` command supports all kinds of accents that are fun to play around with.
You can get a list of all of them by running `say -v "?"`)


### Using the Shell

_If the program immediately exits when you try to run the shell, try upgrading `pry` and `pry-byebug`.
This can be done by running `gem install pry; gem install pry-byebug`._

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
the result may be mysterious.  For example, if I were write the wifi information
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
wifi-wand lsa          # prints available networks detailed information
wifi-wand pr           # prints preferred networks
wifi-wand cy           # cycles the wifi off and on
wifi-wand co a-network a-password # connects to a network requiring a password
wifi-wand co a-network            # connects to a network _not_ requiring a password
wifi-wand t on && say "Internet connected" # Play audible message when Internet becomes connected
```

#### Interactive Shell Commands

When in shell mode, commands generally return the target object (e.g. the array of
available networks) rather than outputting a nicely formatted string. 
This is intentional, so that you can compose expressions and in general
have maximum flexibility. The result may be that `pry` displays 
that returned value in an ugly way.

If you don't need the return value but just want to display the value nicely,
you can use the `fancy_puts` method to output it nicely. An alias `fp` has been
provided for your convenience. You're welcome!  For example:

```
[5] pry(#<WifiWand::CommandLineInterface>)> fp pr.first(3)
[
    [0] "  AIS SMART Login",
    [1] " BubblesLive",
    [2] "#HKAirport Free WiFi"
]
```

For best display results, be sure `awesome_print` is `gem install`ed.
The program will silently use a not-as-nice formatter without it.
(This silence is intentional, so that users who don't want to install
`awesome-print` will not be bothered.)

If you want to suppress output altogether (e.g. if you are using the value in an
expression and don't need to see it displayed,
you can simply append `;nil` to the expression
and `nil` will be value output to the console. For example:

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
model = WifiWand::MacOsModel.new
puts model.available_network_names.to_yaml # etc...
```


**More Examples**

(For brevity, semicolons are used here to put multiple commands on one line, 
but these commands could also each be specified on a line of its own.)

```
# Print out wifi info:
i

# Cycle (off/on) the network then connect to the specified network not requiring a password
> cycle; connect 'my-network'

# Cycle (off/on) the network, then connect to the same network not requiring a password
> @name = network_name; cycle; connect @name

# Cycle (off/on) the network then connect to the specified network using the specified password
> cycle; connect 'my-network', 'my-password'

> @i = i; puts "You are connected on port #{@i[:port]} to #{@i[:network]} on IP address #{@i[:ip_address]}."
You are connected on port en0 to .@ AIS SUPER WiFi on IP address 172.27.145.225.

> puts "There are #{pr.size} preferred networks."
There are 341 preferred networks.

# Delete all preferred networks whose names begin with "TOTTGUEST", the hard way:
> pr.grep(/^TOTTGUEST/).each { |n| rm(n) }

# Delete all preferred networks whose names begin with "TOTTGUEST", the easy way.
# rm can take multiple network names, but they must be specified as separate parameters; thus the '*'.
> rm(*pr.grep(/^TOTTGUEST/))

# Define a method to wait for the Internet connection to be active.
# (This functionality is included in the `till` command.)
# Call it, then output celebration message:
[17] pry(#<WifiWandView>)> def wait_for_internet; loop do; break if ci; sleep 0.5; end; end
[18] pry(#<WifiWandView>)> wait_for_internet; puts "Connected!"
Connected!

# Same, but using a lambda instead of a method so we can use a variable name
# and not need to worry about method name collision:
@wait_for_internet = -> { loop do; break if ci; sleep 0.5; end }
@wait_for_internet.() ; puts "Connected!"
Connected!
```


### Dependent Gems

Currently, the only gems used directly by the program are:

* `pry`, to provide the interactive shell
* `awesome_print` (optional), to more nicely format output in non-interactive mode

So the user can avoid installing gems altogether as long as they don't need to use the interactive shell,
and as long as they are comfortable with the less pretty output.


### Password Lookup Oddity

You may find it odd (I did, anyway) that even if you issue the password command 
(`mac_wifi pa a-network-name`) using sudo, you will still be prompted 
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


### License

MIT License (see LICENSE.txt)

### Shameless Ad

I am available for consulting, development, tutoring, training, troubleshooting, etc.

You can contact me via GMail, Twitter, Github, and LinkedIn, as _keithrbennett_.
