# Info Command - Detailed Network Information

## Overview

The `info` command provides comprehensive network and WiFi information beyond what the `status` command
offers. Use this when you need detailed data about your network configuration and status.

## Breaking Change: Connectivity API

In this major release, the old boolean-style `connected_to_internet?` API has
been replaced by `internet_connectivity_state`.

For `info`, that means connectivity is exposed as explicit state values:

- Ruby / interactive shell: symbols such as `:reachable` and `:indeterminate`
- JSON output: strings such as `"reachable"` and `"indeterminate"`

## Basic Usage

Get detailed network information:

```bash
wifiwand info
```

## Information Provided

The `info` command returns a hash containing:

### Network Connection Details
- **WiFi Status**: On or Off
- **Association Status**: Whether the WiFi interface appears associated with a network
- **Connected Network**: Current SSID, or nil when disconnected or SSID identity is unavailable
- **BSSID**: Current access point MAC address, or nil when unavailable
- **Signal Quality**: Current connection quality as a structured value/unit hash, such as
  `{ value: -65, unit: :dbm }` on macOS or `{ value: 72, unit: :percent }` on Ubuntu
- **SSID Identity Available**: Whether the current SSID name is known and usable
- **SSID Identity Status**: `available`, `unavailable`, `not_connected`, or `unknown`
- **SSID Identity Warning**: Explanation when macOS privacy redaction prevents exact SSID identity
- **IPv4 Addresses** (`ipv4_addresses`): Local IPv4 address(es)
- **IPv6 Addresses** (`ipv6_addresses`): Local IPv6 address(es)
- **MAC Address**: WiFi interface MAC address

### Connectivity Status
- **TCP Working**: Can establish TCP connections
- **DNS Working**: Can resolve domain names
- **Captive Portal Login Required**: `:yes`, `:no`, or `:unknown`
- **Internet Connectivity State**: `:reachable`, `:unreachable`, or `:indeterminate`

`internet_connectivity_state` is derived from TCP, DNS, and
whether captive portal login is currently required:

| TCP | DNS | Captive portal login required | Internet connectivity |
|-----|-----|--------------------------------|-----------------------|
| pass | pass | `:no` | `:reachable` |
| fail | any | any | `:unreachable` |
| any | fail | any | `:unreachable` |
| pass | pass | `:yes` | `:unreachable` |
| pass | pass | `:unknown` | `:indeterminate` |

### Network Configuration
- **Nameservers**: Currently configured DNS servers

### Interface Information
- **WiFi Interface**: Name of the WiFi interface (e.g., `en0` on macOS)
- **Default Route Interface**: Which interface handles default traffic
- **Timestamp**: Time when the info snapshot was collected

## Comparing with Status Command

| Feature | `status` | `info` |
|---------|----------|--------|
| WiFi power state | ✓ | ✓ |
| Connected network | ✓ | ✓ |
| BSSID | | ✓ |
| Signal quality | ✓ | ✓ |
| Connectivity (TCP/DNS) | ✓ | ✓ |
| IPv4 addresses | | ✓ |
| IPv6 addresses | | ✓ |
| MAC address | | ✓ |
| Nameservers | | ✓ |
| Timestamp | | ✓ |
| Output format | Single line | Structured data |

**Use `status`** for: Quick connectivity checks, monitoring, automation
**Use `info`** for: Detailed network diagnostics, configuration review, troubleshooting

## Output Formats

The `info` command supports multiple output formats via the `-o` flag:

### Pretty Print (Default)
```bash
wifiwand info
```

Returns formatted output suitable for humans.

### JSON
```bash
wifiwand -o j info
```

Perfect for parsing in scripts or sending to other tools:

```bash
wifiwand -o j info | jq -r '.ipv4_addresses | join(", ")'
```

Example connectivity fields in JSON:

```json
{
  "internet_tcp_connectivity": true,
  "dns_working": true,
  "captive_portal_login_required": "no",
  "internet_connectivity_state": "reachable"
}
```

Example connectivity fields in interactive Ruby:

```ruby
data = info
data['captive_portal_login_required'] #=> :no
data['internet_connectivity_state'] #=> :reachable
```

Local address fields are split by address family:

```ruby
data['ipv4_addresses'] #=> ['192.168.1.100']
data['ipv6_addresses'] #=> ['fe80::1', '2001:db8::100']
```

### Pretty JSON
```bash
wifiwand -o J info
```

Outputs indented JSON for humans while preserving JSON parsing semantics.

### YAML
```bash
wifiwand -o y info
```

Useful for configuration files or documentation.

### Inspect
```bash
wifiwand -o i info
```

Outputs in Ruby inspect format.

### Puts
```bash
wifiwand -o p info
```

Outputs via Ruby's standard `puts`.

### Pretty Print
```bash
wifiwand -o P info
```

Outputs using Ruby's standard pretty printer.

### Amazing Print
```bash
wifiwand -o a info
```

Outputs using `amazing_print`. ANSI color follows stdout: color is enabled when stdout is a terminal and
suppressed when output is piped or redirected. Pipe through `tee` if you want terminal-readable plain output
while also saving or forwarding it.

## Practical Examples

### Get Your IPv4 Addresses

```bash
wifiwand -o j info | jq -r '.ipv4_addresses[]?'
```

### Get Your IPv6 Addresses

```bash
wifiwand -o j info | jq -r '.ipv6_addresses[]?'
```

### Check All Nameservers

```bash
wifiwand -o j info | jq '.nameservers'
```

### Troubleshoot Network Issues

When having network problems, `info` gives you the complete picture:

```bash
#!/bin/bash
echo "=== Network Troubleshooting ==="
echo ""
echo "Full Network Info:"
wifiwand info
echo ""
echo "Quick Status:"
wifiwand status
echo ""
echo "Internet connectivity state:"
wifiwand -o p ci
```

### Extract Specific Data for Logging

```bash
#!/bin/bash
# Log key network info periodically
while true; do
  wifiwand -o j info | jq -r '"[\(.ipv4_addresses | join(", "))] Connected to: \(.network // "N/A") | Internet: \(.internet_connectivity_state)"'
  sleep 300
done >> network-log.txt
```

### Check Network Configuration

```bash
#!/bin/bash
# Display network configuration
echo "Connected Network:"
wifiwand -o j info | jq '.network'

echo "IPv4 Addresses:"
wifiwand -o j info | jq -r '.ipv4_addresses | join(", ")'

echo "IPv6 Addresses:"
wifiwand -o j info | jq -r '.ipv6_addresses | join(", ")'

echo "Nameservers:"
wifiwand -o j info | jq '.nameservers'
```

## Interactive Shell Usage

In interactive shell mode (`wifiwand shell`), you can use the full power of Ruby to work with info:

```ruby
[1] pry(#<WifiWand::CommandLineInterface>)> data = info
# Returns the info hash

[2] pry(#<WifiWand::CommandLineInterface>)> data['ipv4_addresses']
# Get IPv4 addresses

[3] pry(#<WifiWand::CommandLineInterface>)> data.keys
# See all available fields

[4] pry(#<WifiWand::CommandLineInterface>)> data['internet_connectivity_state'] == :reachable
# Explicit reachability check
```

## Performance Considerations

Like `status`, the `info` command takes several seconds to complete due to comprehensive system queries. Each
call requires querying:
- WiFi power state
- Network connection information
- Connectivity status (DNS/TCP checks)
- Interface configuration

Don't use `info` in tight loops. If you're checking frequently, use `status` for quick checks and fall back to
`info` only when you need the detailed data.

## Verbose Mode

Use verbose mode to see which OS commands are being executed:

```bash
wifiwand -v true info
```

This is helpful for understanding how the detailed information is gathered or debugging connectivity issues.
