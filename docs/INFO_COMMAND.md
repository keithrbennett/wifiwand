# Info Command - Detailed Network Information

## Overview

The `info` command provides comprehensive network and WiFi information beyond what the `status` command offers. Use this when you need detailed data about your network configuration and status.

## Basic Usage

Get detailed network information:

```bash
wifi-wand info
```

## Information Provided

The `info` command returns a hash containing:

### Network Connection Details
- **WiFi Status**: On or Off
- **Connected Network**: Current SSID (or nil if not connected)
- **IP Address**: Local IP address(es)
- **MAC Address**: WiFi interface MAC address

### Connectivity Status
- **TCP Working**: Can establish TCP connections
- **DNS Working**: Can resolve domain names
- **Internet Connected**: Both TCP and DNS working

### Network Configuration
- **Nameservers**: Currently configured DNS servers
- **Preferred Networks**: Saved/remembered network SSIDs
- **Available Networks**: Networks currently in range

### Interface Information
- **WiFi Interface**: Name of the WiFi interface (e.g., `en0` on macOS)
- **Default Route Interface**: Which interface handles default traffic

## Comparing with Status Command

| Feature | `status` | `info` |
|---------|----------|--------|
| WiFi power state | ✓ | ✓ |
| Connected network | ✓ | ✓ |
| Connectivity (TCP/DNS) | ✓ | ✓ |
| IP address | | ✓ |
| MAC address | | ✓ |
| Nameservers | | ✓ |
| Preferred networks | | ✓ |
| Available networks | | ✓ |
| Output format | Single line | Structured data |

**Use `status`** for: Quick connectivity checks, monitoring, automation
**Use `info`** for: Detailed network diagnostics, configuration review, troubleshooting

## Output Formats

The `info` command supports multiple output formats via the `-o` flag:

### Pretty Print (Default)
```bash
wifi-wand info
```

Returns formatted output suitable for humans.

### JSON
```bash
wifi-wand -o j info
```

Perfect for parsing in scripts or sending to other tools:

```bash
wifi-wand -o j info | jq '.ip_address'
```

### YAML
```bash
wifi-wand -o y info
```

Useful for configuration files or documentation.

### Inspect
```bash
wifi-wand -o i info
```

Outputs in Ruby inspect format.

## Practical Examples

### Get Your IP Address

```bash
wifi-wand -o j info | jq -r '.ip_address'
```

### Check All Nameservers

```bash
wifi-wand -o j info | jq '.nameservers'
```

### List All Preferred Networks

```bash
wifi-wand -o j info | jq '.preferred_networks'
```

### Troubleshoot Network Issues

When having network problems, `info` gives you the complete picture:

```bash
#!/bin/bash
echo "=== Network Troubleshooting ==="
echo ""
echo "Full Network Info:"
wifi-wand info
echo ""
echo "Quick Status:"
wifi-wand status
echo ""
echo "Is Internet working?"
wifi-wand ci
```

### Extract Specific Data for Logging

```bash
#!/bin/bash
# Log key network info periodically
while true; do
  wifi-wand -o j info | jq -r '"[\(.ip_address)] Connected to: \(.connected_network // "N/A")"'
  sleep 300
done >> network-log.txt
```

### Check Network Configuration

```bash
#!/bin/bash
# Display network configuration
echo "Connected Network:"
wifi-wand -o j info | jq '.connected_network'

echo "IP Address:"
wifi-wand -o j info | jq '.ip_address'

echo "Nameservers:"
wifi-wand -o j info | jq '.nameservers'

echo "Preferred Networks:"
wifi-wand -o j info | jq '.preferred_networks | length'
echo "networks are saved"
```

## Interactive Shell Usage

In interactive shell mode (`wifi-wand -s`), you can use the full power of Ruby to work with info:

```ruby
[1] pry(#<WifiWand::CommandLineInterface>)> data = info
# Returns the info hash

[2] pry(#<WifiWand::CommandLineInterface>)> data['ip_address']
# Get just the IP address

[3] pry(#<WifiWand::CommandLineInterface>)> data['preferred_networks'].length
# Count saved networks

[4] pry(#<WifiWand::CommandLineInterface>)> data.keys
# See all available fields
```

## Performance Considerations

Like `status`, the `info` command takes several seconds to complete due to comprehensive system queries. Each call requires querying:
- WiFi power state
- Network connection information
- Connectivity status (DNS/TCP checks)
- Interface configuration
- Available networks

Don't use `info` in tight loops. If you're checking frequently, use `status` for quick checks and fall back to `info` only when you need the detailed data.

## Verbose Mode

Use verbose mode to see which OS commands are being executed:

```bash
wifi-wand -v info
```

This is helpful for understanding how the detailed information is gathered or debugging connectivity issues.
