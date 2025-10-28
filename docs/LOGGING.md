# WiFi Event Logging

## Overview

The `log` command continuously polls your WiFi connection status at regular intervals and logs events when state changes occur. This is useful for:

- Monitoring WiFi connectivity issues over time
- Debugging network problems
- Tracking connection drops and reconnections
- Creating an audit trail of network state changes

## ⚠️ Important: macOS Status Observation Timing

**On macOS, each WiFi status check takes several seconds to complete.**

The status observation involves querying multiple OS utilities (`networksetup`, `system_profiler`, network commands) to determine WiFi power state, network connection, TCP connectivity, and DNS resolution. This inherently takes several seconds.

**This means the `--interval` option sets a MINIMUM time between polls, not an exact polling frequency.**

### Example: `--interval 1`

When you run:
```bash
wifi-wand log --interval 1
```

You might expect to see status checks every 1 second. However:
- Status check takes several seconds
- After check completes, waits 1 second before next check
- **Actual polling interval: several seconds plus 1 second**

### Effective Polling Intervals

| `--interval` Setting | Status Check Duration | Actual Interval |
|-----|---|---|
| 1 second | Several seconds | Several seconds + 1 |
| 5 seconds (default) | Several seconds | Several seconds + 5 |
| 0.5 seconds | Several seconds | Several seconds + 0.5 |
| 0 seconds | Several seconds | Several seconds |

### Practical Implications

- **For monitoring**: Use default `--interval 5` or higher
- **For debugging fast events**: Events that happen within the status check duration of each other will be captured together in a single observation
- **For real-time accuracy**: Set `--interval 0` to check again immediately after each status completes (but still limited by status check duration)

**Note**: This timing limitation is due to macOS's underlying system APIs and utilities (`networksetup`, `system_profiler`, network commands), not our design. Ubuntu does not have this issue and status checks complete much faster.

## Basic Usage

### Default Behavior (stdout only)

The simplest invocation logs events to the terminal:

```bash
wifi-wand log
```

Output appears as events occur:
```
[2025-10-28 23:44:14] Event logging started (polling every 5s)
[2025-10-28 23:44:19] Current state: WiFi ON, connected to "HomeNetwork", internet available
[2025-10-28 23:45:10] Internet unavailable
[2025-10-28 23:45:45] Internet available
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

To see events on the terminal while also saving them to a file:

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

Additive flag that enables stdout output in addition to file output.

- Works with `--file` to output to both destinations
- Default behavior when no output options are specified

### `--interval N`

Wait time between status checks in seconds (default: 5).

**Important**: This is the time to wait AFTER each status check completes, not the total polling frequency. See [macOS Status Observation Timing](#-important-macos-status-observation-timing) above.

```bash
wifi-wand log --interval 2      # Wait 2 sec after each check (total: several seconds + 2)
wifi-wand log --interval 0.5    # Wait 0.5 sec after each check (total: several seconds + 0.5)
wifi-wand log --interval 0      # No wait, check again immediately (total: several seconds)
```

**Practical guidance:**
- **Default (5)**: Recommended for most use cases
- **Higher (10+)**: For long-term monitoring with less system load
- **Lower (0-2)**: Only useful if you're actively debugging and want the fastest possible response time
- **Note**: Setting this very low does NOT improve accuracy; the status check itself takes several seconds

### `--hook PATH`

Path to a hook script for future integration (currently reserved for future use).

```bash
wifi-wand log --hook ~/.config/wifi-wand/hooks/on-event
```

This option is designed for future functionality where hooks could execute custom actions when events occur. The event structure is ready for hook integration.

### `--verbose`, `-v`

Enable verbose logging (shows additional details).

```bash
wifi-wand log --verbose
```

## Event Types

The logger tracks and reports the following event types:

- **WiFi ON** - WiFi radio turned on
- **WiFi OFF** - WiFi radio turned off
- **Connected to "NetworkName"** - Successfully connected to a network
- **Disconnected from "NetworkName"** - Disconnected from the network
- **Internet available** - Internet connectivity became available
- **Internet unavailable** - Internet connectivity was lost

## Log File Format

Each log entry is timestamped in the format:

```
[YYYY-MM-DD HH:MM:SS] Event description
```

Example log file content:

```
[2025-10-28 14:32:15] Event logging started (polling every 5s)
[2025-10-28 14:32:20] Current state: WiFi ON, connected to "HomeNetwork", internet available
[2025-10-28 14:32:25] Internet unavailable
[2025-10-28 14:32:30] Internet available
[2025-10-28 14:45:10] Disconnected from "HomeNetwork"
[2025-10-28 14:45:15] WiFi OFF
```

## Practical Examples

### Monitor WiFi for 1 minute with fast polling

```bash
timeout 60 wifi-wand log --interval 0 --file --stdout
```

**Note**: Even with `--interval 0`, the status check duration limits how frequently observations can occur. This is the fastest possible granularity on macOS.

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

1. **Initial State**: The logger captures and logs the current network state when started
2. **Polling Loop**: At regular intervals (default 5 seconds), the status is queried
3. **Change Detection**: Current state is compared to previous state
4. **Event Emission**: Only changes are logged (no duplicates for unchanged state)
5. **Graceful Shutdown**: Pressing `Ctrl+C` cleanly closes the log file and exits

## Connectivity Checks

The logger evaluates connectivity using the same mechanisms as the `status` command:

- **WiFi Power**: On or Off
- **Network Connection**: Connected to a network (and which one)
- **Internet Availability**: Both DNS and TCP connectivity are working

These checks use appropriate timeouts to avoid false positives from temporary network hiccups.

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

## Future: Hook Integration

The event logging infrastructure is designed with future hook execution in mind. When implemented, hooks will allow custom scripts to execute in response to specific events:

```bash
wifi-wand log --hook ~/.config/wifi-wand/hooks/on-event
```

This would enable:
- Sending notifications when connectivity changes
- Triggering automatic reconnection attempts
- Logging events to external monitoring systems
- Custom automation based on network state changes

The event structure already supports JSON serialization for this future integration.
