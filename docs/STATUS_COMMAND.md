# Status Command and Dynamic Status Display

## Overview

The `status` command (aliased as `s`) displays a concise, single-line summary of your WiFi and internet connectivity status. This command is optimized for accurate, reliable connectivity information and uses intentionally long timeouts to avoid false positives from temporary network slowdowns.

## Basic Usage

### Quick Status Check

Display the current status once:

```bash
wifi-wand status
```

Output:
```
WiFi: ON | Network: "HomeNetwork" | TCP: YES | DNS: YES | Internet: YES
```

### Colorized Output

On terminals that support it, the status is color-coded for at-a-glance readability:

- **Green**: Connected/Working (WiFi ON, TCP/DNS working, Internet available)
- **Red**: Disconnected/Not Working (WiFi OFF, not connected, connectivity issues)
- **Cyan**: Network names

Example output with colors:
```
WiFi: [GREEN]ON[RESET] | Network: [CYAN]"HomeNetwork"[RESET] | TCP: [GREEN]YES[RESET] | DNS: [GREEN]YES[RESET] | Internet: [GREEN]YES[RESET]
```

## Understanding the Status Components

### WiFi Status
- **ON** - WiFi radio is powered on and available
- **OFF** - WiFi radio is powered off

### Network
- Shows the SSID (network name) you're connected to
- If not connected: `N/A`

### TCP Connectivity
- **YES** - TCP connections working (can reach remote servers)
- **NO** - TCP connectivity unavailable

### DNS Connectivity
- **YES** - DNS resolution working (can resolve domain names)
- **NO** - DNS resolution unavailable

### Internet Status
- **YES** - Both TCP and DNS working (internet is available)
- **NO** - Internet is not available (either TCP or DNS not working)

## Connectivity Detection Details

The status command determines connectivity by running checks in parallel for efficiency:

### WiFi Power State
Checked directly via OS commands (`networksetup` on macOS, `nmcli` on Ubuntu).

### Network Connection
Checks which network (if any) is currently connected.

### TCP Connectivity
Attempts to establish a TCP connection to a reliable server with a 5-second timeout. This verifies that the network path to the internet is working.

### DNS Connectivity
Performs a DNS lookup with a 5-second timeout. This verifies that DNS service is available and functional.

### Internet Availability
Determined by the combination of TCP and DNS checks. Internet is considered available only when both are working.

## Status Checking Behavior

### Timeout Values

The status command uses carefully tuned timeout values to balance responsiveness with reliability:

- **TCP timeout**: 5 seconds
- **DNS timeout**: 5 seconds
- **Overall connectivity check**: 6 seconds

These timeouts prevent false negatives from temporary network slowdowns while still providing timely feedback.

### Change Detection

When used in conjunction with the `log` command, the status information is used to detect state changes:

```bash
# In one terminal, monitor state changes
wifi-wand log --file --stdout

# In another terminal, modify WiFi
wifi-wand off          # Watch the log show state change
```

## Use Cases

### Displaying Status Repeatedly

Display status repeatedly on the terminal (useful for monitoring):

```bash
# Display status every 2 seconds
watch -n 2 wifi-wand status

# Or with a loop
while true; do
  clear
  date
  wifi-wand status
  sleep 2
done
```

### JSON Format for Integration

Use JSON output for parsing in other tools:

```bash
wifi-wand -o j status | jq .
```

Returns JSON structure:
```json
{
  "wifi_on": true,
  "network_name": "HomeNetwork",
  "tcp_working": true,
  "dns_working": true,
  "internet_connected": true,
  "ip_address": "192.168.1.100",
  "mac_address": "aa:bb:cc:dd:ee:ff"
}
```

## Status Command vs Info Command

| Feature | `status` | `info` |
|---------|----------|--------|
| Output | Single line | Multi-line detailed data |
| Speed | Fast (5-6 seconds) | Slower (more comprehensive) |
| Connectivity checks | Yes (TCP/DNS) | No |
| For scripts | Good | Better (structured data) |
| For humans | Good (quick check) | Better (comprehensive info) |

## Related Commands

### See Full Details
```bash
wifi-wand info    # Get comprehensive networking information
```

### Monitor Changes Over Time
```bash
wifi-wand log     # Log events as status changes
```

### Wait for State Change
```bash
wifi-wand till on        # Wait until WiFi turns on
wifi-wand till conn      # Wait until internet connected
```

## Practical Examples

### Check if Internet is Available

```bash
# Practical example
if wifi-wand status | grep "Internet: YES" > /dev/null; then
  echo "Internet OK - starting backup"
  # Start backup operation
else
  echo "No internet - postponing backup"
  exit 1
fi
```

### Monitor WiFi Stability During Troubleshooting

```bash
# Start logging in one terminal
wifi-wand log --file debug.log --stdout

# In another terminal, run status repeatedly
watch -n 1 wifi-wand status

# Observe changes in both outputs to identify issues
```

### Create a WiFi Status Dashboard

```bash
#!/bin/bash
# Simple dashboard script
while true; do
  clear
  echo "=== WiFi Status Dashboard ==="
  echo "Time: $(date '+%H:%M:%S')"
  echo "---"
  wifi-wand status
  echo "---"
  echo "IP Address: $(wifi-wand info | grep -i 'ip_address' | head -1)"
  echo ""
  echo "Press Ctrl+C to exit"
  sleep 2
done
```

### Automated Network Recovery

```bash
#!/bin/bash
# Restart WiFi if internet drops
while true; do
  if ! wifi-wand status | grep -q "Internet: YES"; then
    echo "$(date): Internet down, reconnecting..."
    wifi-wand cycle
    sleep 10
  fi
  sleep 30
done
```

## Output Formats

The status command supports different output formats via the `-o` flag:

```bash
# Pretty format (default)
wifi-wand status

# JSON
wifi-wand -o j status

# Pretty JSON
wifi-wand -o k status

# YAML
wifi-wand -o y status

# Inspect
wifi-wand -o i status

# Plain text (puts)
wifi-wand -o p status
```

## Verbose Mode

Use verbose mode to see which OS commands are being executed:

```bash
wifi-wand -v status
```

Shows:
```
[OS Command] networksetup -getairportpower en0
WiFi: ON | Network: "HomeNetwork" | TCP: YES | DNS: YES | Internet: YES
[OS Command] ... (other commands shown)
```

This is useful for understanding how the status is determined or debugging connection issues.

## Color Output Detection

The status command automatically detects if the terminal supports color:

- **TTY (interactive terminal)**: Colors are enabled automatically
- **Piped to file or script**: Colors are disabled
- **Force color**: Set the `FORCE_COLOR` environment variable if needed

Example:
```bash
FORCE_COLOR=true wifi-wand status | less -R
```

## Performance Considerations

### Timeout Impact

The 5-6 second timeout for connectivity checks means:
- Running `status` once takes approximately 5-6 seconds
- Running it frequently (e.g., in a loop) with short sleep times works well
- In watch mode (`watch -n 2`), updates happen every 2 seconds after the initial check completes

### Parallel Execution

The TCP and DNS checks run in parallel using Ruby Fibers:
- Both checks start at the same time
- The result is ready as soon as the slower one completes
- This is much faster than sequential checks would be

### System Load

The status command has minimal impact on system resources:
- No excessive polling
- Network operations only when explicitly requested
- No background processes created
