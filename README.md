# mac-wifi

This script enables the query and management of wifi configuration and environment on a Mac.

It can be run in single-command or interactive mode. Interactive mode uses the `pry` gem,
providing an interface familiar to Rubyists and other REPL users.

It is not necessary to download this repo; this script file is all you need to run the application.

### Usage

Available commands can be seen by using the `h` (or `help`) option. Here is its
output at the time of this writing:

```
➜  mac-wifi git:(master) ✗   ./mac-wifi h

Available commands are:

ci                      = connected to Internet (not just wifi on)?
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
w[ifion]                - is the wifi on?
x[it]                   - exits this program (interactive shell mode only)

When in interactive shell mode:
    * use quotes for string parameters such as method names.
    * for pry commands, use prefix `%`.
```

Internally, it uses several Mac command line utilities. This is not ideal,
I would have preferred OS system calls, but it enabled me to develop
this script quickly and simply.

### Pretty Output

For nicely formatted output of the `info` command, the `awesome_print` gem is used if it is installed;
otherwise, the somewhat less awesome pretty print (`pp`) is used.  
So installation of the `awesome_print` gem is recommended. 
This is accomplished by the following command:

`gem install awesome_print`


### Seeing the Underlying OS Commands and Output

If you would like to see the Mac OS commands and their output, you can do so by setting the
environment variable MAC_WIFI_OPTS to include `-v`. This can be done in the following ways:

```
export MAC_WIFI_OPTS=-v
./mac-wifi i
```

```
MAC_WIFI_OPTS=-v  ./mac-wifi i
```

You may notice that some commands are executed more than once. This is to simplify the application logic
and eliminate the need for the complexity of balancing the speed that a cache offers and the risk
of stale data.


### Troubleshooting

If you try to run the shell, the script will require the `pry` gem, so that will need to be installed.
`pry` in turn requires access to a `readline` library. If you encounter an error relating to finding a
`readline` library, this can be fixed by installing the `pry-coolline` gem: `gem install pry-coolline`.
If you are using the Ruby packaged with Mac OS, or for some other reasonn require root access to install
gems, you will need to precede those commands with `sudo`:

```
sudo gem install pry
sudo gem install pry-coolline
```


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
[4] pry(#<MacWifiView>)> ne  # but any other name starting with 'ne' will still call the method
=> ".@ AIS SUPER WiFi"
[5] pry(#<MacWifiView>)> network_name
=> ".@ AIS SUPER WiFi"
[6] pry(#<MacWifiView>)> ne_xzy123
=> ".@ AIS SUPER WiFi"
``` 

If you don't want to deal with this, you could use global variables, instance variables,
or constants, which will _not_ hide the methods:

```
[1] pry(#<MacWifiView>)> n
[2] pry(#<MacWifiView>)> $n = 123
[3] pry(#<MacWifiView>)> @n = 456
[4] pry(#<MacWifiView>)> N = 789
[5] pry(#<MacWifiView>)> puts n; puts $n; puts @n; puts N
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

### License

MIT License (see LICENSE.txt)

### Shameless Ad

I am available for consulting, development, tutoring, training, troubleshooting, etc.

You can contact me via GMail, Twitter, and Github as _keithrbennett_.
