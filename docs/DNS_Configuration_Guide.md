# DNS Configuration Guide

This guide covers DNS configuration on Ubuntu and macOS, explaining the differences between network management approaches and providing practical commands for each platform.

## Ubuntu (NetworkManager)

### Understanding NetworkManager's Approach

Ubuntu uses **NetworkManager** which operates on **connection profiles** rather than interfaces directly. This means:

- DNS settings are tied to specific network connections (e.g., "Home WiFi", "Office WiFi")
- Each Wi-Fi network can have different DNS settings
- Settings persist automatically when reconnecting to the same network

### Key Commands

#### Check Current Configuration
```bash
# Show all devices and DNS settings
nmcli device show | grep -E "DEVICE|TYPE|CONNECTION|IP4.DNS"

# Show DNS for specific interface
nmcli device show wlp0s20f3 | grep DNS

# List active connections
nmcli connection show --active
```

#### Configure DNS Settings
```bash
# Set custom DNS servers for a connection
sudo nmcli connection modify "Wi-Fi Connection Name" ipv4.dns "1.1.1.1 8.8.8.8"

# Ignore automatic DNS from router/DHCP
sudo nmcli connection modify "Wi-Fi Connection Name" ipv4.ignore-auto-dns yes

# Apply changes by restarting the connection
sudo nmcli connection up "Wi-Fi Connection Name"
```

#### Example: Complete DNS Setup
```bash
# 1. Identify your connection
nmcli connection show --active

# 2. Configure DNS (replace "WFC_Globe" with your connection name)
sudo nmcli connection modify "WFC_Globe" ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli connection modify "WFC_Globe" ipv4.ignore-auto-dns yes
sudo nmcli connection up "WFC_Globe"

# 3. Verify changes
nmcli device show wlp0s20f3 | grep DNS
```

### Why Connection Names vs Interface Names?

NetworkManager uses **connection profiles** because:
- One interface can connect to multiple networks (different Wi-Fi SSIDs)
- Each network connection can have different configurations
- Settings persist per connection, not per interface

**Example:**
- Interface: `wlp0s20f3` (the physical WiFi adapter)
- Connections: `Home_WiFi`, `Office_WiFi`, `Coffee_Shop` (different network profiles)

## macOS DNS Management

### Understanding macOS Approach

macOS handles DNS at the **network service level**:

- DNS settings apply to network services (Wi-Fi, Ethernet, etc.)
- By default, all Wi-Fi networks share the same DNS settings
- Uses "Locations" for different network configurations (advanced)

### Key Commands

#### Check Current Configuration
```bash
# Show all DNS configuration
scutil --dns

# Show DNS servers for specific service
networksetup -getdnsservers Wi-Fi
networksetup -getdnsservers Ethernet

# List all network services
networksetup -listallnetworkservices
```

#### Configure DNS Settings
```bash
# Set DNS servers for Wi-Fi
sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8

# Set DNS servers for Ethernet
sudo networksetup -setdnsservers Ethernet 1.1.1.1 8.8.8.8

# Clear DNS servers (use automatic)
sudo networksetup -setdnsservers Wi-Fi "Empty"
```

#### Advanced: Using Locations
```bash
# Create a new location
networksetup -createlocation "Work" populate

# Switch to a location
networksetup -switchtolocation "Work"

# List all locations
networksetup -listlocations
```

## Key Differences Between Ubuntu and macOS

| Aspect | Ubuntu (NetworkManager) | macOS |
|--------|------------------------|-------|
| **Scope** | Per connection profile | Per network service |
| **Granularity** | Each Wi-Fi network can have different DNS | All Wi-Fi networks share same DNS by default |
| **Persistence** | ✅ **Permanent per connection** - survives reboots & reconnections | ✅ **Permanent for service** - survives reboots & network changes |
| **Management** | Connection-based | Service-based |
| **Flexibility** | High - each network independent | Low - all networks use same DNS |
| **Example** | "Home WiFi" uses 1.1.1.1, "Work WiFi" uses 8.8.8.8 | All Wi-Fi uses 1.1.1.1 unless using Locations |

### DNS Persistence Behavior

Both systems **permanently modify** DNS settings when you configure custom servers:

**Ubuntu:**
- Custom DNS settings are saved to the **specific connection profile**
- Settings persist across reboots and reconnections to that network
- Each Wi-Fi network maintains independent DNS configuration
- Other networks are unaffected

**macOS:**
- Custom DNS settings apply to the **entire Wi-Fi service**
- Settings persist across reboots and apply to ALL Wi-Fi networks
- Cannot have different DNS per network (without using Locations)
- All Wi-Fi connections use the same custom DNS

### Practical Examples

**Ubuntu Scenario:**
```bash
# Connect to work network and set custom DNS
nmcli connection up "Work_WiFi"
sudo nmcli connection modify "Work_WiFi" ipv4.dns "8.8.8.8 1.1.1.1"
sudo nmcli connection modify "Work_WiFi" ipv4.ignore-auto-dns yes
sudo nmcli connection up "Work_WiFi"

# Switch to home network (keeps its own DNS settings)
nmcli connection up "Home_WiFi"  # Still uses router DNS (192.168.1.1)

# Switch back to work (automatically uses custom DNS)
nmcli connection up "Work_WiFi"  # Automatically uses 8.8.8.8, 1.1.1.1
```

**macOS Scenario:**
```bash
# Set custom DNS for all Wi-Fi networks
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 1.1.1.1

# All Wi-Fi networks now use custom DNS
networksetup -setairportnetwork en0 "Work_WiFi" password    # Uses 8.8.8.8
networksetup -setairportnetwork en0 "Home_WiFi" password    # Uses 8.8.8.8  
networksetup -setairportnetwork en0 "Coffee_Shop"          # Uses 8.8.8.8
```

## Common DNS Servers

| Provider | Primary | Secondary | Purpose |
|----------|---------|-----------|---------|
| Cloudflare | 1.1.1.1 | 1.0.0.1 | Fast, privacy-focused |
| Google | 8.8.8.8 | 8.8.4.4 | Reliable, widely used |
| Quad9 | 9.9.9.9 | 149.112.112.112 | Security-focused, blocks malicious domains |
| OpenDNS | 208.67.222.222 | 208.67.220.220 | Content filtering options |

## Troubleshooting

### Ubuntu
```bash
# Check if NetworkManager is running
systemctl status NetworkManager

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Reset DNS cache
sudo systemd-resolve --flush-caches

# Check DNS resolution
dig @1.1.1.1 example.com
```

### Understanding systemd-resolved on Ubuntu

Ubuntu uses **systemd-resolved** which creates a local DNS stub resolver at `127.0.0.53`. This is normal and expected:

```bash
# /etc/resolv.conf will show:
nameserver 127.0.0.53

# To see actual DNS servers being used:
resolvectl status

# Or check NetworkManager connection directly:
nmcli connection show "Your-WiFi-Name" | grep -i dns
```

**Why this matters:**
- `/etc/resolv.conf` shows `127.0.0.53` (systemd-resolved stub)
- The actual DNS servers are configured in NetworkManager
- Applications use the stub, which forwards to the real DNS servers
- This is why WiFiWand needed to read from NetworkManager, not `/etc/resolv.conf`

### macOS
```bash
# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Check DNS resolution
dig @1.1.1.1 example.com
nslookup example.com
```

## Best Practices

1. **Use reliable DNS providers** - Choose DNS servers with good uptime and privacy policies
2. **Test after changes** - Verify DNS resolution works after configuration changes
3. **Document your settings** - Keep track of which networks use which DNS servers
4. **Consider security** - Use DNS providers that block malicious domains (like Quad9)
5. **Have fallbacks** - Configure both primary and secondary DNS servers