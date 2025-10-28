# macOS OS Command Usage

### os-command-use-mac-warp_composite.md

### Mon Sep  8 07:34:00 PM UTC 2025

macOS WiFi management uses `networksetup` as the primary interface for configuration, `system_profiler` for information gathering, and optional Swift/CoreWLAN for advanced features. **Key concept**: macOS uses service names (like "Wi-Fi", "AirPort") that map to hardware interfaces (like "en0", "en1").

## Network Management Tools Overview

On macOS, `wifi-wand` uses a variety of tools to manage network settings:

- **`networksetup`**: A versatile command for configuring network services, including Wi-Fi power, preferred networks, and DNS settings.
- **`system_profiler`**: Provides detailed hardware and software information in JSON format. Used to get comprehensive network and WiFi information.
- **`security`**: The command-line interface to the macOS Keychain for securely retrieving stored Wi-Fi passwords.
- **Swift Helpers**: Custom Swift scripts (`WifiNetworkConnector`, `WifiNetworkDisconnector`) for reliable connection management using CoreWLAN framework.

---

## Command Usage by Category

### Hardware and Service Detection

**`networksetup -listallhardwareports`**
- **Description**: Lists all hardware ports to dynamically detect Wi-Fi service name and interface
- **Dynamic Values**: None
- **Base Model Method(s)**: `detect_wifi_service_name`, `detect_wifi_interface_using_networksetup`
- **CLI Commands**: All WiFi operations (automatic service/interface detection)
- **Notes**: Service names vary across systems ("Wi-Fi", "AirPort", "Wireless", etc.)

**`system_profiler -json SPNetworkDataType`**
- **Description**: Gets detailed network information in JSON format to detect Wi-Fi interface name (e.g., en0)
- **Dynamic Values**: None
- **Base Model Method(s)**: `detect_wifi_interface`
- **CLI Commands**: All WiFi operations (automatic interface detection)

**`sw_vers -productVersion`**
- **Description**: Detects the current macOS version for diagnostics and logging
- **Dynamic Values**: None
- **Base Model Method(s)**: `detect_macos_version`
- **CLI Commands**: Initialization helpers

### Interface Validation

**`networksetup -listpreferredwirelessnetworks {interface} 2>/dev/null`**
- **Description**: Validates if an interface is WiFi-capable by attempting to list preferred networks
- **Dynamic Values**: `{interface}` - Interface name to validate
- **Base Model Method(s)**: `is_wifi_interface?`
- **CLI Commands**: Interface validation (internal)

### Radio Control

**`networksetup -getairportpower {interface}`**
- **Description**: Check if WiFi radio is enabled (returns pattern ending with "): On" or "): Off")
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `wifi_on?`
- **CLI Commands**: `w` (wifi status), and internal checks in most WiFi operations

**`networksetup -setairportpower {interface} [on|off]`**
- **Description**: Enables or disables WiFi radio for specified interface
- **Dynamic Values**: `{interface}` - WiFi interface name, `[on|off]` - desired state
- **Base Model Method(s)**: `wifi_on`, `wifi_off`
- **CLI Commands**: `on` (enable wifi), `of` (disable wifi)

### Network Discovery and Status

**`system_profiler -json SPAirPortDataType`**
- **Description**: Gets comprehensive WiFi information including available networks, signal strength, and current connection
- **Dynamic Values**: None
- **Base Model Method(s)**: `_available_network_names`, `_connected_network_name`, `airport_data` (private), `connection_security_type`
- **CLI Commands**: `a` (available networks), `ne` (network name), `i` (info), security type detection
- **Notes**: Can be slower than other methods but provides most detailed information

### Network Connection

**`swift {script_path} {network_name} [password]`**
- **Description**: Connect to network using Swift/CoreWLAN (preferred method when available)
- **Dynamic Values**: `{script_path}` - Path to WifiNetworkConnector.swift, `{network_name}` - SSID, `{password}` - network password (optional)
- **Base Model Method(s)**: `os_level_connect_using_swift`
- **CLI Commands**: `co` (connect - preferred method)
- **Notes**: More reliable than networksetup method, better error handling

**`networksetup -setairportnetwork {interface} {network_name} [password]`**
- **Description**: Connect to network using networksetup (fallback method when Swift/CoreWLAN unavailable)
- **Dynamic Values**: `{interface}` - WiFi interface name, `{network_name}` - SSID, `{password}` - network password (optional)
- **Base Model Method(s)**: `os_level_connect_using_networksetup`
- **CLI Commands**: `co` (connect - fallback method)

### Connection Management

**`networksetup -listpreferredwirelessnetworks {interface}`**
- **Description**: List all saved/preferred wireless networks, sorted case-insensitively
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `preferred_networks`
- **CLI Commands**: `pr` (preferred networks)

**`sudo networksetup -removepreferredwirelessnetwork {interface} {network_name}`**
- **Description**: Remove a network from the preferred networks list (requires admin privileges)
- **Dynamic Values**: `{interface}` - WiFi interface name, `{network_name}` - Network name to remove
- **Base Model Method(s)**: `remove_preferred_network`
- **CLI Commands**: `f` (forget network)

### Disconnection

**`swift {script_path}`**
- **Description**: Disconnect from current network using Swift/CoreWLAN (preferred method)
- **Dynamic Values**: `{script_path}` - Path to WifiNetworkDisconnector.swift
- **Base Model Method(s)**: `_disconnect` (preferred method)
- **CLI Commands**: `d` (disconnect - preferred)

**`[sudo] ifconfig {interface} disassociate`**
- **Description**: Disconnect from current network using ifconfig (fallback methods)
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `_disconnect` (fallback methods)
- **CLI Commands**: `d` (disconnect - fallback when Swift/CoreWLAN unavailable)
- **Notes**: Tries sudo first, then without sudo as secondary fallback

### Password Retrieval

**`security find-generic-password -D "AirPort network password" -a {network_name} -w 2>&1`**
- **Description**: Retrieve stored password for a preferred network from macOS keychain
- **Dynamic Values**: `{network_name}` - Network name to retrieve password for
- **Base Model Method(s)**: `_preferred_network_password`
- **CLI Commands**: `pa` (password for preferred network)
- **Notes**: Exit codes mapped to specific keychain errors (44: not found, 45: access denied, 128: cancelled, 51: non-interactive mode)

### Network Information

**`ipconfig getifaddr {interface}`**
- **Description**: Get IPv4 address assigned to WiFi interface
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `_ip_address`
- **CLI Commands**: `i` (info)

**`ifconfig {interface} | awk '/ether/{print $2}'`**
- **Description**: Get MAC address of WiFi interface
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `mac_address`
- **CLI Commands**: `i` (info)

**`route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}'`**
- **Description**: Get network interface used for default internet route
- **Dynamic Values**: None
- **Base Model Method(s)**: `default_interface`
- **CLI Commands**: Internal routing queries

### DNS Management

**`scutil --dns`**
- **Description**: Get comprehensive DNS configuration from System Configuration framework (preferred method)
- **Dynamic Values**: None
- **Base Model Method(s)**: `nameservers_using_scutil`, `nameservers`
- **CLI Commands**: `na` (get nameservers - preferred method)
- **Notes**: Most accurate DNS information on macOS

**`networksetup -getdnsservers {service_name}`**
- **Description**: Get currently configured DNS servers for WiFi service (fallback method)
- **Dynamic Values**: `{service_name}` - WiFi service name from `detect_wifi_service_name`
- **Base Model Method(s)**: `nameservers_using_networksetup`
- **CLI Commands**: `na` (get nameservers - fallback method)
- **Notes**: May show "There aren't any DNS Servers set" for automatic DNS

**`networksetup -setdnsservers {service_name} [empty|{dns_string}]`**
- **Description**: Set custom DNS servers for WiFi service, or clear them with 'empty'
- **Dynamic Values**: `{service_name}` - WiFi service name, `{dns_string}` - space-separated DNS IPs
- **Base Model Method(s)**: `set_nameservers`
- **CLI Commands**: `na` (set nameservers), `na clear` (clear nameservers)

### System Integration

**`open -a {application_name}`**
- **Description**: Open application using system default handler
- **Dynamic Values**: `{application_name}` - Application name or path
- **Base Model Method(s)**: `open_application`
- **CLI Commands**: `ro` (resource open - applications)

**`open {resource_url}`**
- **Description**: Open URL or file using system default handler
- **Dynamic Values**: `{resource_url}` - URL or file path to open
- **Base Model Method(s)**: `open_resource`
- **CLI Commands**: `ro` (resource open - URLs/files)

### QR Code Generation

**`which qrencode`**
- **Description**: Verify `qrencode` command is available (install: brew install qrencode)
- **Dynamic Values**: None
- **Base Model Method(s)**: `generate_qr_code` (via QrCodeGenerator helper)
- **CLI Commands**: `qr` (generate QR code - prerequisite check)

**`qrencode -t ANSI {wifi_qr_string}`**
- **Description**: Generate ANSI QR code to stdout for WiFi connection
- **Dynamic Values**: `{wifi_qr_string}` - WiFi QR format string (WIFI:T:security;S:ssid;P:password;H:false;;)
- **Base Model Method(s)**: `generate_qr_code` (via QrCodeGenerator helper)
- **CLI Commands**: `qr -` (generate QR code to stdout)

**`qrencode [-t {format}] -o {filename} {wifi_qr_string}`**
- **Description**: Generate QR code file for WiFi connection
- **Dynamic Values**: `{format}` - Output format (PNG default, SVG, EPS), `{filename}` - Output filename, `{wifi_qr_string}` - WiFi QR format string
- **Base Model Method(s)**: `generate_qr_code` (via QrCodeGenerator helper)
- **CLI Commands**: `qr [filename]` (generate QR code to file)

### Swift/CoreWLAN Capability Detection

**`swift -e 'import CoreWLAN'`**
- **Description**: Test if Swift and CoreWLAN framework are available for advanced WiFi operations
- **Dynamic Values**: None
- **Base Model Method(s)**: `swift_and_corewlan_present?`
- **CLI Commands**: Internal capability detection (determines preferred vs fallback methods)

**`which swift`**
- **Description**: Verify Swift command is available (optional - install with: xcode-select --install)
- **Dynamic Values**: None
- **Base Model Method(s)**: `validate_os_preconditions`
- **CLI Commands**: All commands (initialization check)

### Public IP Information

**`curl -s ipinfo.io`**
- **Description**: Fetches public IP metadata; used only when connectivity appears up
- **Dynamic Values**: None
- **Base Model Method(s)**: `BaseModel#public_ip_address_info` (used by `#wifi_info`)
- **CLI Commands**: `i` (info)

---

## macOS WiFi Management Concepts

Important macOS-specific concepts for WiFi management:

### Service Names vs Interface Names
macOS uses service names (e.g., "Wi-Fi", "AirPort") for `networksetup` commands and interface names (e.g., "en0", "en1") for low-level operations. The system dynamically detects both since service names vary across systems.

### Dual Connection Methods
The system prefers Swift/CoreWLAN when available (more reliable, better error handling) but falls back to `networksetup` when Swift or CoreWLAN are unavailable.

### Keychain Integration
Network passwords are stored in the macOS keychain with specific error codes for access control:
- 44: Password not found
- 45: Access denied (user rejected)
- 128: User cancelled authentication
- 51: Non-interactive mode (no UI available)

### Dynamic Service Detection
WiFi service names vary across systems ("Wi-Fi", "AirPort", "Wireless", etc.), so the system dynamically detects the correct service name pattern during initialization.

### Version Compatibility
Wifi Wand relies on feature detection (e.g., CoreWLAN availability). Version lookups are recorded for diagnostics but no fixed minimum macOS release is enforced.

### DNS Hierarchy
DNS resolution uses multiple sources with `scutil --dns` as the preferred method (most accurate) and `networksetup -getdnsservers` as fallback for compatibility.
