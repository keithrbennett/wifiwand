# mac-wifi

The `mac-wifi` script installed by this gem (or otherwise copied) enables the query and management of wifi configuration and environment on a Mac.
The code encapsulates the Mac OS specific logic in a minimal class to more easily add support for other operating systems,
but as of now, only Mac OS is supported. (Feel free to add an OS!)

It can be run in single-command or interactive mode. Interactive mode uses the `pry` gem,
providing an interface familiar to Rubyists and other 
[REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop) users.

It is not necessary to download this repo or even install this gem; the `bin/mac-wifi` script file is all you need to run the application.


### Usage

Available commands can be seen by using the `h` (or `help`) option. Here is its
output at the time of this writing:

```
➜  mac-wifi git:(master) ✗   ./mac-wifi h

mac-wifi version 1.1.0 -- Available commands are:

ci                      - connected to Internet (not just wifi on)?
co[nnect] network-name  - turns wifi on, connects to network-name
cy[cle]                 - turns wifi off, then on, preserving network selection
d[isconnect]            - disconnects from current network, does not turn off wifi
h[elp]                  - prints this help
i[nfo]                  - prints wifi-related information
lsp[referred]           - lists preferred (not necessarily available) networks
lsa[vailable]           - lists available networks
n[etwork_name]          - name (SSID) of currently connected network
on                      - turns wifi on
of[f]                   - turns wifi off
pa[ssword] network-name - shows password for preferred network-name
q[uit]                  - exits this program (interactive shell mode only)
r[m] network-name       - removes network-name from the preferred networks list
s[hell]                 - opens an interactive pry shell (command line only)
t[ill]                  - returns when the desired Internet connection state is true. Options:
                          'on'/:on or 'off'/:off
                          wait interval, in seconds (optional, defaults to 0.5 seconds)
w[ifion]                - is the wifi on?
x[it]                   - exits this program (interactive shell mode only)

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


### Seeing the Underlying OS Commands and Output

If you would like to see the Mac OS commands and their output, you can do so by setting the
environment variable MAC_WIFI_OPTS to include `-v` (for _verbose_).
This can be done in the following ways:

```
export MAC_WIFI_OPTS=-v
./mac-wifi i
```

...or...

```
MAC_WIFI_OPTS=-v  ./mac-wifi i
```

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

**If the program immediately exits when you try to run the shell, try upgrading `pry` and `pry-byebug`.
This can be done by running `gem install pry; gem install pry-byebug`.**

The shell, invoked with the `s` command on the command line, provides an interactive
session. It can be useful when:

* you want to issue multiple commands
* you want to combine commands
* you want the data in a format not provided by this application
* you want to incorporate these commands into other Ruby code interactively
* you want to combine the results of commands with other OS commands 
  (you can shell out to run other command line programs by preceding the command with a period (`.`).


### Using Variables in the Shell

There are a couple of things (that may be surprising) to keep in mind
when using the shell. They relate to the fact that local variables
and method calls use the same notation in Ruby (use of parentheses
in a method call is optional):

1) In Ruby, when both a method and a local variable have the same name,
the local variable will override the method name. Therefore, local variables
may override this app's commands.  For example:

```
[1] pry(#<MacWifiView>)> n  # network_name command
=> ".@ AIS SUPER WiFi"
[2] pry(#<MacWifiView>)> n = 123  # override it with a local variable
=> 123
[3] pry(#<MacWifiView>)> n  # 'n' no longer calls the method
=> 123
[4] pry(#<MacWifiView>)> ne  # but any other name that `network_name starts with will still call the method
=> ".@ AIS SUPER WiFi"
[5] pry(#<MacWifiView>)> network_name
=> ".@ AIS SUPER WiFi"
[6] pry(#<MacWifiView>)> ne_xzy123
"ne_xyz123" is not a valid command or option. If you intend for this to be a string literal, use quotes.
``` 

If you don't want to deal with this, you could use global variables, instance variables,
or constants, which will _not_ hide the methods:

```
[7] pry(#<MacWifiView>)> N = 123
[8] pry(#<MacWifiView>)> @n = 456
[9] pry(#<MacWifiView>)> $n = 789
[10] pry(#<MacWifiView>)> puts n, N, @n, $n
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
[1] pry(#<MacWifiView>)> File.write('x.txt', info)
=> 431
```

However, if I forget to quote the filename:

```
[2] pry(#<MacWifiView>)> File.write(x.txt, info)
➜  mac-wifi git:(master) ✗  
```

What happened? `x.txt` was assumed by Ruby to be a method name.
`method_missing` was called, and since `x.txt` starts with `x`,
the exit method was called, exiting the program.

Bottom line is, be careful to quote your strings, and you're probably better off using 
constants or instance variables if you want to create variables in your shell. 



### Examples

#### Single Command Invocations

```
mac-wifi i            # prints out wifi info
mac-wifi lsa          # prints available networks
mac-wifi lsp          # prints preferred networks
mac-wifi cy           # cycles the wifi off and on
mac-wifi co a-network a-password # connects to a network requiring a password
mac-wifi co a-network            # connects to a network _not_ requiring a password
mac-wifi t on && say "Internet connected" # Play audible message when Internet becomes connected
```

#### Interactive Shell Commands

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

> puts "There are #{lsp.size} preferred networks."
There are 341 preferred networks.

# Delete all preferred networks whose names begin with "TOTTGUEST", the hard way:
> lsp.grep(/^TOTTGUEST/).each { |n| rm(n) }

# Delete all preferred networks whose names begin with "TOTTGUEST", the easy way.
# rm can take multiple network names, but they must be specified as separate parameters; thus the '*'.
> rm(*lsp.grep(/^TOTTGUEST/))

# Define a method to wait for the Internet connection to be active.
# (This functionality is included in the `till` command.)
# Call it, then output celebration message:
[17] pry(#<MacWifiView>)> def wait_for_internet; loop do; break if ci; sleep 0.5; end; end
[18] pry(#<MacWifiView>)> wait_for_internet; puts "Connected!"
Connected!

# Same, but using a lambda instead of a method so we can use a variable name
# and not need to worry about method name collision:
@wait_for_internet = -> { loop do; break if ci; sleep 0.5; end }
@wait_for_internet.() ; puts "Connected!"
Connected!
```


### Distribution, or Why All The Code is in One Humongous File

This code would be neater and easier to read if each class were in a file of its own.
The reason everything is in one file is to simplify distribution for some users.
Although installation as a gem is simple, being able to download a single file may work better when:

* the user wants to install the script once, rather than once per Ruby version and/or gemset.
* the user needs or wants to specify the exact location of the script (e.g. `~/bin`),
and/or does not want it buried in the gem directory tree (e.g. `/Users/kbennett/.rvm/gems/ruby-2.4.0/bin/mac-wifi`).
* the user is not familiar with Ruby and does not want to use the `gem` command
* the user is concerned about security and would prefer to install a single file to a known location
rather than run the gem installation
* installing gems is controlled by the user's organization, and getting authorization is not practical
* installing gems requires root access, and the user does not have root access

That said, installation as a gem is highly recommended, since:

* this will greatly simplify acquiring future fixes and enhancements
* if the user wants to use the shell mode, they will need to `gem install pry` anyway

Currently, the only gems used by the program are:

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
automate it (e.g. `mac-wifi cycle && mac-wifi connect a-network a-password`). Also, you might find it handy
to create a script for your most commonly used networks containing something like this:

```
mac-wifi  connect  my-usual-network  its-password
```


### License

MIT License (see LICENSE.txt)

### Shameless Ad

I am available for consulting, development, tutoring, training, troubleshooting, etc.

You can contact me via GMail, Twitter, and Github as _keithrbennett_.
