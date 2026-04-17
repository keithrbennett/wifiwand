# WiFi Event Logging

## Overview

The `log` command continuously monitors WiFi power, network connection, and internet connectivity, logging
events when any of these states change. This is useful for:

- Monitoring WiFi power state changes
- Tracking network connections and disconnections
- Monitoring internet connectivity issues over time
- Debugging network problems
- Tracking outages and reconnections
- Creating an audit trail of connectivity state changes

## Breaking Change Context

The main library connectivity API is now `internet_connectivity_state`, which
returns `:reachable`, `:unreachable`, or `:indeterminate`.

The log command still emits the historical event names `internet_on` and
`internet_off`, but those events are derived from the explicit state model:

- `internet_on` means the state changed to `:reachable`
- `internet_off` means the state changed to `:unreachable`
- no internet event is emitted for `:indeterminate`

If the current state is indeterminate when logging starts, the initial snapshot
will say `internet unknown`.

## Basic Usage

### Default Behavior (stdout only)

The simplest invocation logs events to the terminal:

```bash
wifi-wand log
```

Output appears as events occur:
```
[2025-10-28T23:44:14Z] Event logging started (polling every 5s)
[2025-10-28T23:44:19Z] Current state: WiFi on, connected to MyNetwork, internet available
[2025-10-28T23:45:10Z] WiFi OFF
[2025-10-28T23:45:15Z] Disconnected from MyNetwork
[2025-10-28T23:45:20Z] Internet unavailable
[2025-10-28T23:45:45Z] WiFi ON
[2025-10-28T23:45:50Z] Connected to MyNetwork
[2025-10-28T23:45:55Z] Internet available
```

Press `Ctrl+C` to stop logging.

### Logging to a File

#### Default log file location (current directory)

```bash
wifi-wand log --file
```

Creates `wifiwand-events.log` in the current directory with events logged to file only (no stdout output).

#### Custom file location

```bash
wifi-wand log --file /path/to/my-wifi-log.txt
```

Logs to the specified file path instead of stdout.

### Outputting to Both File and stdout

When you add any destination besides stdout, the command assumes you want to silence the console unless you
opt back in. To see events on the terminal while also saving them to a file, include `--stdout` explicitly:

```bash
wifi-wand log --file --stdout
```

Or with a custom file path:

```bash
wifi-wand log --file /tmp/wifi-events.log --stdout
```

## Options

### `--file [PATH]`

Enables file logging.

- `--file` - Uses default filename `wifiwand-events.log` in current directory
- `--file /path/to/file.log` - Uses specified file path

When this option is used alone, output goes to file only (stdout is disabled).

**Note:** The directory must already exist. The command will not create parent directories.

### `--stdout`

Explicitly enables stdout output. Standard output is used by default, but it is disabled automatically once
`--file` is specified unless `--stdout` is also provided.

- Include after `--file` to keep seeing events in the terminal
- Without any other destinations, stdout is already active by default

### `--interval N`

Time between connectivity checks in seconds (default: 5). Must be greater than 0.

```bash
wifi-wand log --interval 2      # check every 2 seconds
wifi-wand log --interval 0.5    # check every 0.5 seconds
wifi-wand log --interval 10     # check every 10 seconds
```

**Practical guidance:**
- **Default (5)**: Recommended for most use cases
- **Higher (10+)**: For long-term monitoring with less system load
- **Lower (1-2)**: For faster outage detection when actively debugging

### `--verbose`, `-v`

Enable verbose logging (shows additional details).

```bash
wifi-wand log --verbose
```

## Event Types

The logger tracks and reports the following event types:

| Event | Description |
|-------|-------------|
| **WiFi ON** | WiFi power was turned on |
| **WiFi OFF** | WiFi power was turned off |
| **Connected to \<network\>** | Connected to a WiFi network |
| **Disconnected from \<network\>** | Disconnected from a WiFi network |
| **Internet available** | Internet connectivity became available |
| **Internet unavailable** | Internet connectivity was lost |

### Event Emission Order

When multiple state changes occur in a single poll, events are emitted in this order:

1. **WiFi power** (wifi_on/wifi_off)
2. **Network connection** (connected/disconnected)
3. **Internet connectivity** (internet_on/internet_off)

These event names are retained CLI/log vocabulary. The source of truth for the
underlying state is still `internet_connectivity_state`.

This ensures that related state changes are logged in a logical sequence.

### Network Roaming

When the network name changes from one non-nil value to another (e.g., "NetworkA" to "NetworkB"), both events
are emitted in this order:

1. `Disconnected from NetworkA`
2. `Connected to NetworkB`

## Log File Format

Each log entry is timestamped in ISO-8601 format:

```
[YYYY-MM-DDTHH:MM:SSZ] Event description
```

Example log file content:

```
[2025-10-28T14:32:15Z] Event logging started (polling every 5s)
[2025-10-28T14:32:20Z] Current state: WiFi on, connected to MyNetwork, internet available
[2025-10-28T14:32:25Z] WiFi OFF
[2025-10-28T14:32:30Z] Disconnected from MyNetwork
[2025-10-28T14:32:35Z] Internet unavailable
[2025-10-28T14:32:45Z] WiFi ON
[2025-10-28T14:32:50Z] Connected to MyNetwork
[2025-10-28T14:32:55Z] Internet available
```

## Practical Examples

### Monitor WiFi for 1 minute with fast polling

```bash
timeout 60 wifi-wand log --interval 0.1 --file --stdout
```

Use a small interval like 0.1 for rapid polling.

### Continuously log to a dated file

```bash
wifi-wand log --file "wifi-$(date +%Y-%m-%d).log"
```

### Log in background while working

```bash
# Start logging in background
wifi-wand log --file wifi-events.log &

# Do your work, then check the log
tail -20 wifi-events.log

# Or kill the background job when done
kill %1
```

### Debug a specific network problem

```bash
# Start detailed logging with fast polling
wifi-wand log --interval 1 --file debug.log --stdout

# Try the operation that's causing problems
# ... do something ...

# Stop with Ctrl+C and examine the log
cat debug.log
```

## How It Works

1. **Initial State**: The logger captures and logs the current WiFi state (power, network, internet) when
   started
2. **Polling Loop**: At regular intervals (default 5 seconds), the following are queried:
   - `wifi_on?` - WiFi power state
   - `connected?` - Whether the interface is associated
   - `connected_network_name` - Currently connected network
   - `internet_connectivity_state` - Explicit internet state, checked on every poll
3. **Change Detection**: Current state is compared to previous state
4. **Event Emission**: Only actual changes are logged, in the order: WiFi power → Network → Internet
5. **Graceful Shutdown**: Pressing `Ctrl+C` cleanly closes the log file and exits

## Status Checks

The logger monitors three aspects of WiFi state:

1. **WiFi Power**: Whether WiFi is turned on or off
2. **Network Connection**: The name of the connected WiFi network (SSID)
3. **Internet Connectivity**: Whether internet access is available
   - Derived directly from `internet_connectivity_state` on every poll
   - May still report reachable internet when WiFi is off or unassociated if another uplink, such as Ethernet,
     is active
   - `:indeterminate` is preserved internally and reported as `internet unknown`
     in the initial-state line
   - Transition events are emitted only when both the previous and current
     states are explicit (`:reachable` or `:unreachable`)

Unlike older boolean-style docs, connectivity is not always known with
certainty. An indeterminate state means TCP and DNS succeeded but captive-portal
checks could not reach a conclusion.

### macOS Performance Note

On macOS, `connected_network_name` can be slow without the Swift/CoreWLAN helper installed (see
[MACOS_SETUP.md](./MACOS_SETUP.md)). This affects logging performance on macOS systems without the helper.

## File Permission Errors

If the specified log file path is not writable:

```bash
wifi-wand log --file /root/wifi.log  # Assuming you're not root
# Error: Cannot open log file /root/wifi.log: Permission denied
```

Solution: Ensure the directory exists and you have write permissions:

```bash
touch ~/wifi-events.log               # Create in home directory
wifi-wand log --file ~/wifi-events.log
```

## Use Cases

### Network Troubleshooting

Keep a log running while experiencing network issues to identify patterns:

```bash
wifi-wand log --file network-debug.log --stdout
# ... reproduce the issue ...
# Review the log to see what happened
```

### Monitoring WiFi Stability

Track WiFi reliability over time:

```bash
wifi-wand log --file ~/logs/wifi-$(date +%Y-%m-%d).log
# Let it run for hours or days
# Analyze logs to identify problem times
```

### Automated Network Monitoring

Create a script to monitor WiFi and take action when issues occur:

```bash
#!/bin/bash
wifi-wand log --file /var/log/wifi-events.log &
LOG_PID=$!

# In another terminal:
tail -f /var/log/wifi-events.log | while read line; do
  if echo "$line" | grep -q "Internet unavailable"; then
    # Take action (e.g., send alert, restart networking, etc.)
    echo "Internet down! $(date)" >> /var/log/wifi-alerts.log
  fi
done
```
