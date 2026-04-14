# Status Command and Dynamic Status Display

## Overview

The `status` command (aliased as `s`) displays a concise, single-line summary of your WiFi, current network,
DNS, and internet connectivity status. This command is optimized for accurate, reliable connectivity
information and uses intentionally long timeouts to avoid false positives from temporary network slowdowns.

## Breaking Change: Explicit Connectivity States

In this major release, internet connectivity is no longer modeled as a simple
boolean. The underlying library API now uses `internet_connectivity_state`
(`:reachable`, `:unreachable`, `:indeterminate`), and the status command exposes
that same model in structured output via `internet_state`.

Human-readable `status` output still shows `DNS: YES`/`NO`/`WAIT` and
`Internet: YES`/`NO`/`UNKNOWN`, while machine-readable output carries the
explicit state values.

## Basic Usage

### Quick Status Check

Display the current status once:

```bash
wifi-wand status
```

Normal output:
```
WiFi: ✅ ON | WiFi Network: HomeNetwork | DNS: ✅ YES | Internet: ✅ YES
```

When a captive portal is detected (e.g., hotel or coffee shop that requires a login):
```
WiFi: ✅ ON | WiFi Network: HotelWiFi | DNS: ✅ YES | Internet: ❌ NO | ⚠️ Captive Portal Login Required
```

### Colorized Output

On terminals that support it, the status is color-coded for at-a-glance readability:

- **Green**: Working/Available (WiFi ON, Internet available)
- **Red**: Off/Unavailable (WiFi OFF, Internet unavailable)
- **Cyan**: Network names
- **Yellow**: Warning states (captive portal detected, pending checks, or no network)

## Understanding the Status Components

### WiFi Status
- **ON** - WiFi radio is powered on and available
- **OFF** - WiFi radio is powered off

### WiFi Network
- Shows the SSID (network name) you're connected to
- If not connected: `[none]`

### DNS Status
- **YES** - DNS resolution is working
- **NO** - DNS resolution failed
- **WAIT** - The DNS check is still in progress

### Internet Status
- **YES** - TCP connectivity, DNS resolution, and no captive portal all confirmed
- **NO** - Internet is not available (TCP failure, DNS failure, or captive portal detected)
- **UNKNOWN** - TCP and DNS worked, but captive-portal checks could not determine the result

### Captive Portal Login Required *(shown only when detected)*
- Appears as `⚠️ Captive Portal Login Required` appended to the status line
- Only shown when a captive portal is **confidently** detected (TCP and DNS work, but HTTP
  connectivity checks show portal interception)
- Not shown when internet is simply down (TCP or DNS failure)

## Captive Portal Detection

A captive portal is a network that intercepts HTTP traffic to redirect users to a login page
(common in hotels, airports, coffee shops, etc.). wifi-wand detects this by:

1. Checking TCP connectivity (layer 4)
2. Checking DNS resolution
3. If both pass, making HTTP requests to known endpoints and verifying each
   endpoint's expected response contract

For some endpoints that contract is just an HTTP status code. For others it is
the combination of status code and expected response body.

If step 3 fails while steps 1–2 pass, a captive portal is confidently detected and
`captive_portal_login_required` is set to `:yes` in the status data.

## Machine-Readable Output

The `dns_working`, `internet_state`, `captive_portal_state`, and
`captive_portal_login_required` fields are present in all machine-readable output formats.

In JSON they appear as strings. In Ruby-oriented formats such as inspect/YAML or
in the interactive shell, they appear as symbols.

If you are scripting against `wifi-wand`, prefer machine-readable output such as JSON (`-o j`)
instead of parsing the human-formatted status line. Structured output is simpler to consume and
less likely to change over time.

### Key: `dns_working`

| Value | Meaning |
|-------|---------|
| `true` | DNS resolution succeeded |
| `false` | DNS resolution failed, was skipped because WiFi is off, or errored |
| `nil` | Temporary streaming-progress state before checks complete |

### Key: `internet_state`

| Value | Meaning |
|-------|---------|
| `"reachable"` | TCP, DNS, and captive portal checks all confirmed Internet access |
| `"unreachable"` | TCP failed, DNS failed, or a captive portal was detected |
| `"indeterminate"` | TCP and DNS worked, but captive portal status could not be determined |
| `"pending"` | Temporary streaming-progress state before checks complete |

### Key: `captive_portal_state`

| Value | Meaning |
|-------|---------|
| `"free"` | No captive portal detected |
| `"present"` | Captive portal detected |
| `"indeterminate"` | Captive portal status could not be determined |

### Key: `captive_portal_login_required`

| Value       | Meaning                                                        |
|-------------|----------------------------------------------------------------|
| `"yes"`     | Captive portal confidently detected; login required            |
| `"no"`      | No captive portal (or WiFi is off / no TCP+DNS connectivity)   |
| `"unknown"` | In-progress / unknown (only during streaming progress updates) |

### JSON example

```bash
wifi-wand -o j status | jq .
```

Normal connected state:
```json
{
  "wifi_on": true,
  "network_name": "HomeNetwork",
  "dns_working": true,
  "internet_state": "reachable",
  "captive_portal_state": "free",
  "captive_portal_login_required": "no"
}
```

Captive portal detected:
```json
{
  "wifi_on": true,
  "network_name": "HotelWiFi",
  "dns_working": true,
  "internet_state": "unreachable",
  "captive_portal_state": "present",
  "captive_portal_login_required": "yes"
}
```

Indeterminate result:
```json
{
  "wifi_on": true,
  "network_name": "CafeWiFi",
  "dns_working": true,
  "internet_state": "indeterminate",
  "captive_portal_state": "indeterminate",
  "captive_portal_login_required": "unknown"
}
```

### YAML example

```bash
wifi-wand -o y status
```

```yaml
---
:wifi_on: true
:network_name: HotelWiFi
:dns_working: true
:internet_state: :unreachable
:captive_portal_state: :present
:captive_portal_login_required: :yes
```

## Connectivity Detection Details

The status command determines connectivity by running checks in parallel for efficiency:

### WiFi Power State
Checked directly via OS commands (`networksetup` on macOS, `nmcli` on Ubuntu).

### Network Connection
Checks which network (if any) is currently connected.

### Internet Availability
Determined by three sequential layers:
1. **TCP Connectivity** — attempts TCP connections to reliable well-known hosts
2. **DNS Resolution** — verifies DNS lookups work
3. **Captive Portal Check** — makes HTTP requests to known endpoints; a wrong response
   code indicates portal interception

Internet is considered available only when all three pass.

## Status Checking Behavior

### Timeout Values

The status command uses carefully tuned timeout values to balance responsiveness with reliability:

- **TCP timeout**: 5 seconds
- **DNS timeout**: 5 seconds
- **HTTP captive portal timeout**: configurable (see TimingConstants)
- **Overall connectivity check**: 6 seconds

These timeouts prevent false negatives from temporary network slowdowns while still providing timely feedback.

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

### Detect Captive Portal Programmatically

```bash
# Exit non-zero if captive portal login is required
if wifi-wand -o j status | jq -e '.captive_portal_login_required == "yes"' > /dev/null; then
  echo "Captive portal detected — please log in before proceeding"
  exit 1
fi
```

### Check if Internet is Available

```bash
if wifi-wand -o j status | jq -e '.internet_state == "reachable"' > /dev/null; then
  echo "Internet OK - starting backup"
elif wifi-wand -o j status | jq -e '.internet_state == "indeterminate"' > /dev/null; then
  echo "Internet state unknown - retrying later"
  exit 2
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
wifi-wand till wifi_on       # Wait until WiFi radio turns on
wifi-wand till wifi_off      # Wait until WiFi radio turns off
wifi-wand till associated    # Wait until associated with an SSID (WiFi layer)
wifi-wand till internet_on   # Wait until Internet becomes reachable
wifi-wand till internet_off  # Wait until Internet becomes unreachable
```

## Status Command vs Info Command

| Feature                   | `status`                         | `info`                          |
|---------------------------|----------------------------------|---------------------------------|
| Output                    | Single line                      | Multi-line detailed data        |
| Speed                     | Fast                             | Slower (more comprehensive)     |
| Connectivity checks       | Yes (TCP/DNS/captive portal)     | Yes (same checks)               |
| Captive portal detection  | Yes (in status data + display)   | Yes (`captive_portal_state` field) |
| For scripts               | Better with `-o j`               | Better (structured data)        |
| For humans                | Good (quick check)               | Better (comprehensive info)     |
