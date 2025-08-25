# Demo Materials

This directory contains materials for creating demonstrations and presentations of wifi-wand.

## Files

### `demo-wifi-wand.sh`
A wrapper script that provides anonymized output for sensitive commands while running real wifi-wand commands for safe operations.

**Usage:**
```bash
# From the demo directory
./demo-wifi-wand.sh info
./demo-wifi-wand.sh avail_nets -o json
./demo-wifi-wand.sh wifi_on

# Or from the project root
demo/demo-wifi-wand.sh info
```

**Features:**
- Anonymizes sensitive data (network names, IP addresses, passwords)
- Passes through safe commands to real wifi-wand
- Supports all output formats (-o json, -o yaml, etc.)
- Maintains realistic timing and behavior

### `video-script.md`
Complete script for a 5-minute video introduction to wifi-wand, including:
- Command examples with sample output
- Narrator text and timing breakdowns
- Technical notes for video production

## Demo Data

The demo script uses consistent anonymized data:
- **Network Name**: "CafeBleu_5G"
- **IP Address**: "192.168.1.105"
- **Interface**: "wlp0s20f3" (Linux) 
- **MAC Address**: "aa:bb:cc:dd:ee:ff"
- **Available Networks**: CafeBleu_5G, CoffeeShop_Guest, HomeNetwork_2.4G, LibraryWiFi, xfinitywifi

## Usage Tips

1. **For Video Recording**: Use `demo-wifi-wand.sh` instead of `wifi-wand` to get consistent, anonymized output
2. **For Live Demos**: The script provides predictable results while still running real commands under the hood
3. **For Testing**: Safe to run without affecting your actual network configuration (for demo commands)

## Security Notes

- Demo script never modifies actual network settings for sensitive operations
- Real network operations (on/off, connect, disconnect) are passed through to actual wifi-wand
- Passwords shown are fictional and not related to any real networks