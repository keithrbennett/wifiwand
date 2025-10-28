# macOS OS Command Usage

### os-command-use-mac-claude.md

### Mon Sep  8 04:55:20 PM UTC 2025

macOS WiFi management uses `networksetup` as the primary interface for configuration, `system_profiler` for information gathering, and optional Swift/CoreWLAN for advanced features. **Key concept**: macOS uses service names (like "Wi-Fi", "AirPort") that map to hardware interfaces (like "en0", "en1").

## Command Usage by Category

### Hardware and Service Detection

**`networksetup -listallhardwareports`**
- Description: Lists all hardware ports to dynamically detect Wi-Fi service name and interface
- Dynamic values: None
- Base model method(s): `detect_wifi_service_name`, `detect_wifi_interface_using_networksetup`
- CLI commands: All WiFi operations (automatic service/interface detection)

**`system_profiler -json SPNetworkDataType`**
- Description: Gets detailed network information in JSON format to detect Wi-Fi interface name (e.g., en0)
- Dynamic values: None
- Base model method(s): `detect_wifi_interface`
- CLI commands: All WiFi operations (automatic interface detection)

**`sw_vers -productVersion`**
- Description: Detects current macOS version for compatibility validation
- Dynamic values: None
- Base model method(s): `detect_macos_version`
- CLI commands: Initialization (version checking)

### Interface Validation

**`networksetup -listpreferredwirelessnetworks {interface} 2>/dev/null`**
- Description: Validates if an interface is WiFi-capable by attempting to list preferred networks
- Dynamic values: `{interface}` - Interface name to validate
- Base model method(s): `is_wifi_interface?`
- CLI commands: Interface validation (internal)

### Radio Control

**`networksetup -getairportpower {interface}`**
- Description: Check if WiFi radio is enabled (returns pattern ending with "): On" or "): Off")
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `wifi_on?`
    - CLI commands: `w` (wifi status), and internal checks in most WiFi operations

**`networksetup -setairportpower {interface} on`**
- Description: Enables WiFi radio for specified interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `wifi_on`
- CLI commands: `on` (enable wifi)

**`networksetup -setairportpower {interface} off`**
- Description: Disables WiFi radio for specified interface  
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `wifi_off`
- CLI commands: `of` (disable wifi)

### Network Discovery and Status

**`system_profiler -json SPAirPortDataType`**
- Description: Gets comprehensive WiFi information including available networks, signal strength, and current connection
- Dynamic values: None
- Base model method(s): `_available_network_names`, `_connected_network_name`, `airport_data` (private), `connection_security_type`
- CLI commands: `a` (available networks), `ne` (network name), `i` (info), security type detection

### Network Connection

**`networksetup -setairportnetwork {interface} {network_name}`**
- Description: Connect to open network using networksetup (fallback method)
- Dynamic values: `{interface}` - WiFi interface name, `{network_name}` - SSID to connect to
- Base model method(s): `os_level_connect_using_networksetup`
- CLI commands: `co` (connect to open network - fallback)

**`networksetup -setairportnetwork {interface} {network_name} {password}`**
- Description: Connect to secured network with password using networksetup (fallback method)
- Dynamic values: `{interface}` - WiFi interface name, `{network_name}` - SSID to connect to, `{password}` - network password
- Base model method(s): `os_level_connect_using_networksetup` 
- CLI commands: `co` (connect with password - fallback)

**`swift {script_path} {network_name}`**
- Description: Connect to open network using Swift/CoreWLAN (preferred method when available)
- Dynamic values: `{script_path}` - Path to WifiNetworkConnector.swift, `{network_name}` - SSID to connect to
- Base model method(s): `os_level_connect_using_swift`
- CLI commands: `co` (connect to open network - preferred)

**`swift {script_path} {network_name} {password}`**
- Description: Connect to secured network using Swift/CoreWLAN (preferred method when available)
- Dynamic values: `{script_path}` - Path to WifiNetworkConnector.swift, `{network_name}` - SSID to connect to, `{password}` - network password
- Base model method(s): `os_level_connect_using_swift`
- CLI commands: `co` (connect with password - preferred)

### Connection Management

**`networksetup -listpreferredwirelessnetworks {interface}`**
- Description: List all saved/preferred wireless networks, sorted case-insensitively
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `preferred_networks`
- CLI commands: `pr` (preferred networks)

**`sudo networksetup -removepreferredwirelessnetwork {interface} {network_name}`**
- Description: Remove a network from the preferred networks list (requires admin privileges)
- Dynamic values: `{interface}` - WiFi interface name, `{network_name}` - Network name to remove
- Base model method(s): `remove_preferred_network`
- CLI commands: `f` (forget network)

### Disconnection

**`swift {script_path}`**
- Description: Disconnect from current network using Swift/CoreWLAN (preferred method)
- Dynamic values: `{script_path}` - Path to WifiNetworkDisconnector.swift
- Base model method(s): `_disconnect` (preferred method)
- CLI commands: `d` (disconnect - preferred)

**`sudo ifconfig {interface} disassociate`**
- Description: Disconnect from current network using ifconfig (fallback method)
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_disconnect` (fallback method)
- CLI commands: `d` (disconnect - fallback when Swift/CoreWLAN unavailable)

**`ifconfig {interface} disassociate`**
- Description: Disconnect from current network without sudo (secondary fallback)
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_disconnect` (secondary fallback)
- CLI commands: `d` (disconnect - secondary fallback)

### Password Retrieval

**`security find-generic-password -D "AirPort network password" -a {network_name} -w 2>&1`**
- Description: Retrieve stored password for a preferred network from macOS keychain
- Dynamic values: `{network_name}` - Network name to retrieve password for
- Base model method(s): `_preferred_network_password`
- CLI commands: `pa` (password for preferred network)

### Network Information

**`ipconfig getifaddr {interface}`**
- Description: Get IPv4 address assigned to WiFi interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_ip_address`
- CLI commands: `i` (info)

**`ifconfig {interface} | awk '/ether/{print $2}'`**
- Description: Get MAC address of WiFi interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `mac_address`
- CLI commands: `i` (info)

**`route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}'`**
- Description: Get network interface used for default internet route
- Dynamic values: None
- Base model method(s): `default_interface`
- CLI commands: Internal routing queries

### DNS Management

**`networksetup -setdnsservers {service_name} empty`**
- Description: Clear custom DNS servers and use automatic DNS (from router/DHCP)
- Dynamic values: `{service_name}` - WiFi service name from `detect_wifi_service_name`
- Base model method(s): `set_nameservers` (when clearing)
- CLI commands: `na clear` (clear nameservers)

**`networksetup -setdnsservers {service_name} {dns_string}`**
- Description: Set custom DNS servers for WiFi service
- Dynamic values: `{service_name}` - WiFi service name, `{dns_string}` - space-separated DNS IPs
- Base model method(s): `set_nameservers`
- CLI commands: `na` (set nameservers)

**`networksetup -getdnsservers {service_name}`**
- Description: Get currently configured DNS servers for WiFi service (may show "There aren't any DNS Servers set")
- Dynamic values: `{service_name}` - WiFi service name from `detect_wifi_service_name`
- Base model method(s): `nameservers_using_networksetup`
- CLI commands: `na` (get nameservers - fallback method)

**`scutil --dns`**
- Description: Get comprehensive DNS configuration from System Configuration framework (preferred method)
- Dynamic values: None
- Base model method(s): `nameservers_using_scutil`, `nameservers`
- CLI commands: `na` (get nameservers - preferred method)

### System Integration

**`open -a {application_name}`**
- Description: Open application using system default handler
- Dynamic values: `{application_name}` - Application name or path
- Base model method(s): `open_application`
- CLI commands: `ro` (resource open - applications)

**`open {resource_url}`**
- Description: Open URL or file using system default handler
- Dynamic values: `{resource_url}` - URL or file path to open
- Base model method(s): `open_resource`
- CLI commands: `ro` (resource open - URLs/files)

### QR Code Generation

**`which qrencode`**
- Description: Verify `qrencode` command is available (install: brew install qrencode)
- Dynamic values: None
- Base model method(s): `generate_qr_code` (via QrCodeGenerator helper)
- CLI commands: `qr` (generate QR code - prerequisite check)

**`qrencode -t ANSI {wifi_qr_string}`**
- Description: Generate ANSI QR code to stdout for WiFi connection
- Dynamic values: `{wifi_qr_string}` - WiFi QR format string (WIFI:T:security;S:ssid;P:password;H:false;;)
- Base model method(s): `generate_qr_code` (via QrCodeGenerator helper)
- CLI commands: `qr -` (generate QR code to stdout)

**`qrencode -o {filename} {wifi_qr_string}`**
- Description: Generate PNG QR code file for WiFi connection (default format)
- Dynamic values: `{filename}` - Output filename, `{wifi_qr_string}` - WiFi QR format string
- Base model method(s): `generate_qr_code` (via QrCodeGenerator helper)
- CLI commands: `qr` (generate QR code to file - PNG format)

**`qrencode -t SVG -o {filename} {wifi_qr_string}`**
- Description: Generate SVG QR code file for WiFi connection
- Dynamic values: `{filename}` - Output filename (*.svg), `{wifi_qr_string}` - WiFi QR format string
- Base model method(s): `generate_qr_code` (via QrCodeGenerator helper)
- CLI commands: `qr filename.svg` (generate QR code to SVG file)

**`qrencode -t EPS -o {filename} {wifi_qr_string}`**
- Description: Generate EPS QR code file for WiFi connection
- Dynamic values: `{filename}` - Output filename (*.eps), `{wifi_qr_string}` - WiFi QR format string
- Base model method(s): `generate_qr_code` (via QrCodeGenerator helper)
- CLI commands: `qr filename.eps` (generate QR code to EPS file)

### Swift/CoreWLAN Capability Detection

**`swift -e 'import CoreWLAN'`**
- Description: Test if Swift and CoreWLAN framework are available for advanced WiFi operations
- Dynamic values: None
- Base model method(s): `swift_and_corewlan_present?`
- CLI commands: Internal capability detection (determines preferred vs fallback methods)

### Prerequisite Validation

**`which swift`**
- Description: Verify Swift command is available (optional - install with: xcode-select --install)
- Dynamic values: None
- Base model method(s): `validate_os_preconditions`
- CLI commands: All commands (initialization check)

### macOS WiFi Management Concepts

Important macOS-specific concepts for WiFi management:

- **Service Names vs Interface Names**: macOS uses service names (e.g., "Wi-Fi", "AirPort") for `networksetup` commands and interface names (e.g., "en0", "en1") for low-level operations. The system dynamically detects both.

- **Dual Connection Methods**: The system prefers Swift/CoreWLAN when available (more reliable, better error handling) but falls back to `networksetup` when Swift or CoreWLAN are unavailable.

- **Keychain Integration**: Network passwords are stored in the macOS keychain with specific error codes for access control (44: not found, 45: access denied, 128: cancelled, 51: non-interactive mode).

- **Dynamic Service Detection**: WiFi service names vary across systems ("Wi-Fi", "AirPort", "Wireless", etc.), so the system dynamically detects the correct service name pattern.

- **Version Compatibility**: Wifi Wand records the macOS version for diagnostics but relies on runtime capability checks instead of a fixed minimum release.

- **DNS Hierarchy**: DNS resolution uses multiple sources with `scutil --dns` as the preferred method (most accurate) and `networksetup -getdnsservers` as fallback.
