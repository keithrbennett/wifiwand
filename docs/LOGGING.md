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

The log command emits JSON Lines. Event objects use an `event` field whose
values include `internet_on` and `internet_off`. Those events are derived from
the explicit state model:

- `internet_on` means the state changed to `:reachable`
- `internet_off` means the state changed to `:unreachable`
- no internet event is emitted for `:indeterminate`

If the current state is indeterminate when logging starts, the initial snapshot
uses `"internet": "unknown"`.

## Basic Usage

### Default Behavior (stdout only)

The simplest invocation logs events to the terminal:

```bash
wifiwand log
```

Output appears as one JSON object per line:
```
{"timestamp":"2025-10-28T19:44:14-04:00","event":"logging_started","interval":5}
{"timestamp":"2025-10-28T19:44:19-04:00","event":"current_state","wifi":true,"connection":"connected","network":"MyNetwork","internet":"available"}
{"timestamp":"2025-10-28T19:45:10-04:00","event":"wifi_off"}
{"timestamp":"2025-10-28T19:45:15-04:00","event":"disconnected","network":"MyNetwork"}
{"timestamp":"2025-10-28T19:45:20-04:00","event":"internet_off"}
{"timestamp":"2025-10-28T19:45:45-04:00","event":"wifi_on"}
{"timestamp":"2025-10-28T19:45:50-04:00","event":"connected","network":"MyNetwork"}
{"timestamp":"2025-10-28T19:45:55-04:00","event":"internet_on"}
```

Press `Ctrl+C` to stop logging.

### Logging to a File

#### Default log file location (current directory)

```bash
wifiwand log --file
```

Creates `wifiwand-events.log` in the current directory with events logged to file only
(no stdout output).

#### Custom file location

```bash
wifiwand log --file /path/to/my-wifi-log.txt
```

Logs to the specified file path instead of stdout.

### Outputting to Both File and stdout

When you add any destination besides stdout, the command assumes you want to silence the console unless you
opt back in. To see events on the terminal while also saving them to a file, include `--stdout` explicitly:

```bash
wifiwand log --file --stdout
```

Or with a custom file path:

```bash
wifiwand log --file /tmp/wifi-events.log --stdout
```

## Options

### `--file [PATH]`

Enables file logging.

- `--file` - Uses default filename `wifiwand-events.log` in current directory
- `--file /path/to/file.log` - Uses specified file path

When this option is used alone, output goes to file only (stdout is disabled).

**Note:** Missing parent directories are created automatically before the log file is opened.

### `--stdout`

Explicitly enables stdout output. Standard output is used by default, but it is disabled automatically once
`--file` is specified unless `--stdout` is also provided.

- Include after `--file` to keep seeing events in the terminal
- Without any other destinations, stdout is already active by default

### `--interval N`

Time between connectivity checks in seconds (default: 5). Must be greater than 0.

```bash
wifiwand log --interval 2      # check every 2 seconds
wifiwand log --interval 5      # check every 5 seconds
wifiwand log --interval 10     # check every 10 seconds
```

**Practical guidance:**
- **Default (5)**: Recommended for most use cases
- **Higher (10+)**: For long-term monitoring with less system load
- **Lower (2-3)**: Useful for faster outage detection when actively debugging
- **Practical minimum (~2 seconds)**: The full `internet_connectivity_state`
  probe often takes about 300-500ms on a working connection and can take
  longer when offline. Below roughly 2 seconds, probe time can start to exceed
  the configured interval and compress the effective polling cadence.
  When the network is down or degraded, an `internet_off` event can be logged
  later than the configured interval because each poll waits for the full
  connectivity probe to finish before the next poll begins.

### `--verbose-logs BOOLEAN`

Enable verbose EventLogger diagnostics, such as field-level lookup failures and log-file initialization.

```bash
wifiwand log --verbose-logs true
```

To disable verbose diagnostics when a default option enables them, pass
`--verbose-logs false`.

### Verbose Mode

Do not combine `wifiwand log` with global `-v true` or `--verbose true`, including through
`WIFIWAND_OPTS`. Global verbose mode prints OS-command tracing as plain text, which would corrupt the JSON
Lines event stream, so `log` raises a `ConfigurationError` instead.

Use command-specific logging diagnostics when you need extra logger detail:

```bash
wifiwand log --verbose-logs true
```

If your shell startup files export `WIFIWAND_OPTS="--verbose true"`, unset it or override it before running
`wifiwand log`. See [ENVIRONMENT_VARIABLES.md](./ENVIRONMENT_VARIABLES.md) for details.

### `--utc BOOLEAN`, `-u BOOLEAN`

Event timestamps use local time by default. The `--utc` option requires an explicit boolean value. To write
timestamps in UTC, pass the global UTC option before the `log` command:

```bash
wifiwand --utc true log # true values: true, t, yes, y, +
wifiwand -u true log    # false values: false, f, no, n, -
```

To force local-time output when a default option enables UTC, pass `--utc false` or `-u false`.

## Event Types

The logger tracks and reports the following event types:

| `event` value | Description |
|---------------|-------------|
| `wifi_on` | WiFi power was turned on |
| `wifi_off` | WiFi power was turned off |
| `connected` | Connected to a WiFi network (`network` field holds the SSID) |
| `disconnected` | Disconnected from a WiFi network (`network` field holds the SSID) |
| `internet_on` | Internet connectivity became available |
| `internet_off` | Internet connectivity was lost |
| `current_state` | Initial snapshot at startup (`wifi`, `connection`, `network`, `internet`) |
| `logging_started` | Logger started (`interval` field holds the poll interval) |
| `logging_stopped` | Logger stopped (usually via Ctrl+C) |
| `logging_terminated` | Logger terminated because of a polling error (`error_class`, `error_message`) |
| `warning` | Operational warning (`message` field holds the text) |
| `debug` | Verbose diagnostic (`message` field holds the text) |

### `current_state` field values

The `current_state` object uses the following values:

- `wifi`: `true` (on), `false` (off), or `null` (state could not be determined)
- `connection`: `"connected"`, `"disconnected"`, or `"unknown"`
- `network`: the SSID string when connected and available, otherwise `null`
- `internet`: `"available"`, `"unavailable"`, or `"unknown"`

### Event Emission Order

When multiple state changes occur in a single poll, events are emitted in this order:

1. **WiFi power** (`wifi_on`/`wifi_off`)
2. **Network connection** (`connected`/`disconnected`)
3. **Internet connectivity** (`internet_on`/`internet_off`)

The source of truth for the underlying state is still
`internet_connectivity_state`.

This ensures that related state changes are logged in a logical sequence.

The logger checks internet reachability with
`internet_connectivity_state` on every poll. `internet_on` and
`internet_off` still represent transitions to the explicit `:reachable`
and `:unreachable` states.

### Network Roaming

When the network name changes from one non-nil value to another (for example,
`NetworkA` to `NetworkB`), both events are emitted in this order:

1. `{"event":"disconnected","network":"NetworkA"}`
2. `{"event":"connected","network":"NetworkB"}`

## Log File Format

Each log entry is one JSON object per line (JSON Lines). Local time is the default:

```json
{"timestamp":"YYYY-MM-DDTHH:MM:SS-04:00","event":"..."}
```

Example log file content:

```json
{"timestamp":"2025-10-28T10:32:15-04:00","event":"logging_started","interval":5}
{"timestamp":"2025-10-28T10:32:20-04:00","event":"current_state","wifi":true,"connection":"connected","network":"MyNetwork","internet":"available"}
{"timestamp":"2025-10-28T10:32:25-04:00","event":"wifi_off"}
{"timestamp":"2025-10-28T10:32:30-04:00","event":"disconnected","network":"MyNetwork"}
{"timestamp":"2025-10-28T10:32:35-04:00","event":"internet_off"}
{"timestamp":"2025-10-28T10:32:45-04:00","event":"wifi_on"}
{"timestamp":"2025-10-28T10:32:50-04:00","event":"connected","network":"MyNetwork"}
{"timestamp":"2025-10-28T10:32:55-04:00","event":"internet_on"}
```

With `--utc true`, timestamps use the UTC `Z` suffix.

## Practical Examples

### Monitor WiFi for 1 minute with quick polling

```bash
timeout 60 wifiwand log --interval 2 --file --stdout
```

Use a 2-second interval when you want faster event detection without pushing
the full connectivity probe below its practical cadence floor.

### Continuously log to a dated file

```bash
wifiwand log --file "wifi-$(date +%Y-%m-%d).log"
```

### Log in background while working

```bash
# Start logging in background
wifiwand log --file wifi-events.log &

# Do your work, then check the log
tail -20 wifi-events.log

# Or kill the background job when done
kill %1
```

### Debug a specific network problem

```bash
# Start detailed logging with fast polling
wifiwand log --interval 2 --file debug.log --stdout

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
   - `connected?` - Whether the WiFi interface is connected or otherwise considered usable by the WiFi model
   - `connected_network_name` - Currently connected network
   - `internet_connectivity_state` - Explicit internet state checked on every poll
3. **Change Detection**: Current state is compared to previous state
4. **Event Emission**: Only actual changes are logged, in the order: WiFi power → Network → Internet
5. **Graceful Shutdown**: Pressing `Ctrl+C` cleanly closes the log file and exits

## Status Checks

The logger monitors three aspects of WiFi state:

1. **WiFi Power**: Whether WiFi is turned on or off
2. **Network Connection**: The name of the connected WiFi network (SSID)
3. **Internet Connectivity**: Whether internet access is available
   - `internet_connectivity_state` is used on every poll
   - May still report reachable internet when WiFi is off or unassociated if another uplink, such as Ethernet,
     is active
   - This differs from `connected?`, which is intentionally WiFi-specific and may be `false` when Ethernet is
     providing the only active uplink
   - `:indeterminate` is preserved internally and reported as
     `"internet": "unknown"` in the initial-state object
   - Transition events are emitted only when both the previous and current
     states are explicit (`:reachable` or `:unreachable`)

Unlike older boolean-style docs, connectivity is not always known with
certainty. An indeterminate state means TCP and DNS succeeded but captive-portal
checks could not reach a conclusion.

### macOS Performance Note

On macOS 14 and later, permission-sensitive read/query operations such as current-network lookup and scans use
the compiled `wifiwand-helper.app` path. Run `wifiwand-macos-setup` from the macOS quick start to install or
repair that helper. The separate direct Swift/CoreWLAN source path is used for connect/disconnect mutations
when available, and has traditional utility fallbacks.

## File Permission Errors

If the specified log file path is not writable:

```bash
wifiwand log --file /root/wifi.log  # Assuming you're not root
# Error: Cannot open log file /root/wifi.log: Permission denied
```

Solution: Choose a path where your user has write permission:

```bash
wifiwand log --file ~/wifi-events.log
wifiwand log --file ~/logs/wifi-events.log
```

## Use Cases

### Network Troubleshooting

Keep a log running while experiencing network issues to identify patterns:

```bash
wifiwand log --file network-debug.log --stdout
# ... reproduce the issue ...
# Review the log to see what happened
```

### Monitoring WiFi Stability

Track WiFi reliability over time:

```bash
wifiwand log --file ~/logs/wifi-$(date +%Y-%m-%d).log
# Let it run for hours or days
# Analyze logs to identify problem times
```

### Automated Network Monitoring

Create a script to monitor WiFi and take action when issues occur:

```bash
#!/bin/bash
wifiwand log --file /var/log/wifi-events.log &
LOG_PID=$!

# In another terminal:
tail -f /var/log/wifi-events.log | while read -r line; do
  if echo "$line" | jq -e '.event == "internet_off"' >/dev/null 2>&1; then
    # Take action (e.g., send alert, restart networking, etc.)
    echo "Internet down! $(date)" >> /var/log/wifi-alerts.log
  fi
done
```
