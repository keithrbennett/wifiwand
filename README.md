# mac-wifi

This script enables the query and management of wifi configuration and environment on a Mac.

It can be run in single-command or interactive mode. Interactive mode uses the `pry` gem,
providing an interface familiar to Rubyists and other REPL users.

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

### License

MIT License (see LICENSE.txt)

### Shameless Ad

I am available for consulting, development, tutoring, training, troubleshooting, etc.

You can contact me via GMail, Twitter, and Github as _keithrbennett_.
