# Ubuntu OS Command Usage

### os-command-use-ubuntu-warp_composite.md

### Mon Sep  8 07:34:00 PM UTC 2025

Ubuntu WiFi management uses NetworkManager (`nmcli`) for connection management and profiles, and `iw` and `ip` for lower-level interface operations. **Key concept**: NetworkManager maintains connection profiles (stored configurations) which are separate from SSIDs. A profile can have any name and connects to a specific SSID.

## Network Management Tools Overview

On Ubuntu, `wifi-wand` relies on several tools for comprehensive WiFi management:

- **`nmcli`**: The command-line interface for NetworkManager. Primary tool for managing connection profiles, radio control, and network operations.
- **`iw`**: Low-level wireless interface tool for device discovery and validation.
- **`ip`**: Network interface configuration tool for addressing and routing information.
- **`xdg-open`**: System default handler for opening URLs and files.

### Connection Profiles vs SSIDs

A key concept in NetworkManager is the distinction between a Wi-Fi network (SSID) and a "connection profile":

- **Wi-Fi Network (SSID)**: The broadcast name of a wireless network (e.g., "MyHomeWiFi")
- **Connection Profile**: A saved set of configurations for a network, including SSID, password, IP settings, DNS servers, etc.

You can have multiple profiles for the same SSID (e.g., "MySSID", "MySSID 1"), which can be a source of confusion. `wifi-wand` manages this by finding the most recently used profile (by timestamp) for a given SSID when performing actions.

---

## Command Usage by Category

### WiFi Interface Detection

**`iw dev | grep Interface | cut -d' ' -f2`**
- **Description**: Finds the first WiFi interface name
- **Dynamic Values**: None
- **Base Model Method(s)**: `detect_wifi_interface`
- **CLI Commands**: All WiFi operations (automatic interface detection)
- **Notes**: Uses piped `grep`/`cut` to extract interface names from `iw` output

**`iw dev {interface} info 2>/dev/null`**
- **Description**: Validates if an interface is WiFi-capable
- **Dynamic Values**: `{interface}` - Interface name to validate
- **Base Model Method(s)**: `is_wifi_interface?`
- **CLI Commands**: Interface validation (internal)

### Radio Control

**`nmcli radio wifi`**
- **Description**: Check if WiFi radio is enabled (returns 'enabled' or 'disabled')
- **Dynamic Values**: None
- **Base Model Method(s)**: `wifi_on?`
- **CLI Commands**: `w` (wifi status), and internal checks in most WiFi operations

**`nmcli radio wifi [on|off]`**
- **Description**: Enables or disables WiFi radio
- **Dynamic Values**: `[on|off]` - desired state
- **Base Model Method(s)**: `wifi_on`, `wifi_off`
- **CLI Commands**: `on` (enable wifi), `of` (disable wifi)

### Network Discovery and Status

**`nmcli -t -f SSID,SIGNAL dev wifi list`**
- **Description**: Lists available networks with signal strength, sorted by signal strength
- **Dynamic Values**: None
- **Base Model Method(s)**: `_available_network_names`
- **CLI Commands**: `a` (available networks)
- **Notes**: Output format is `SSID:SIGNAL`; code sorts descending by signal and de-duplicates SSIDs

**`nmcli -t -f SSID,SECURITY dev wifi list`**
- **Description**: Get security type (WPA2, WPA3, WEP, etc.) for all available networks
- **Dynamic Values**: None
- **Base Model Method(s)**: `get_security_parameter`, `security_parameter`, `connection_security_type`
- **CLI Commands**: `co` (connect - for determining security type), internal security checks
- **Notes**: Maps security to `802-11-wireless-security.psk` for WPA/WPA2/WPA3, `...wep-key0` for WEP

**`nmcli -t -f active,ssid device wifi | egrep '^yes' | cut -d\\: -f2`**
- **Description**: Get SSID of currently connected network (returns SSID, not connection profile name)
- **Dynamic Values**: None
- **Base Model Method(s)**: `_connected_network_name`
- **CLI Commands**: `ne` (network name), `i` (info), status checks

### Network Connection

**`nmcli dev wifi connect {network_name} [password {password}]`**
- **Description**: Connect to network, creating a new connection profile if needed
- **Dynamic Values**: `{network_name}` - SSID to connect to, `{password}` - network password (optional)
- **Base Model Method(s)**: `connect_with_wifi_command` (private method)
- **CLI Commands**: `co` (connect)
- **Notes**: Creates profile if doesn't exist; profile name often matches SSID

**`nmcli connection up {profile_name}`**
- **Description**: Activate existing connection profile by name
- **Dynamic Values**: `{profile_name}` - Connection profile name (often same as SSID)
- **Base Model Method(s)**: `_connect`, `connect_with_wifi_command`, `set_nameservers`
- **CLI Commands**: `co` (connect using existing profile), `na` (apply DNS changes)

### Connection Profile Management

**`nmcli -t -f NAME,TIMESTAMP connection show`**
- **Description**: List connection profiles with timestamps to find most recently used
- **Dynamic Values**: None
- **Base Model Method(s)**: `find_best_profile_for_ssid` (private method)
- **CLI Commands**: `co` (connect - profile selection logic)
- **Notes**: Used to pick most recent profile when duplicates exist for same SSID

**`nmcli connection modify {profile_name} 802-11-wireless-security.psk {password}`**
- **Description**: Update WPA/WPA2/WPA3 password in existing connection profile
- **Dynamic Values**: `{profile_name}` - Connection profile name, `{password}` - new password
- **Base Model Method(s)**: `_connect` (private method, via `get_security_parameter`)
- **CLI Commands**: `co` (connect - update existing profile password)

**`nmcli connection modify {profile_name} 802-11-wireless-security.wep-key0 {password}`**
- **Description**: Update WEP password in existing connection profile
- **Dynamic Values**: `{profile_name}` - Connection profile name, `{password}` - new WEP key
- **Base Model Method(s)**: `_connect` (private method, via `get_security_parameter`)
- **CLI Commands**: `co` (connect - update existing WEP profile password)

**`nmcli -t -f NAME connection show`**
- **Description**: List all saved connection profiles (NetworkManager profiles, not just SSIDs)
- **Dynamic Values**: None
- **Base Model Method(s)**: `preferred_networks`
- **CLI Commands**: `pr` (preferred networks)

**`nmcli connection delete {network_name}`**
- **Description**: Delete a stored connection profile
- **Dynamic Values**: `{network_name}` - Connection profile name to delete
- **Base Model Method(s)**: `remove_preferred_network`
- **CLI Commands**: `f` (forget network)

**`nmcli dev disconnect {interface}`**
- **Description**: Disconnect from current network
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `_disconnect`
- **CLI Commands**: `d` (disconnect)
- **Notes**: Exit code 6 (device not active) is handled as a non-error

### Password Retrieval

**`nmcli --show-secrets connection show {network_name} | grep '802-11-wireless-security.psk:' | cut -d':' -f2-`**
- **Description**: Retrieve stored password for a connection profile
- **Dynamic Values**: `{network_name}` - Connection profile name
- **Base Model Method(s)**: `_preferred_network_password`
- **CLI Commands**: `pa` (password for preferred network)

### Network Information

**`ip -4 addr show {interface} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1`**
- **Description**: Get IPv4 address of WiFi interface
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `_ip_address`
- **CLI Commands**: `i` (info)

**`ip link show {interface} | grep ether | awk '{print $2}'`**
- **Description**: Get MAC address of WiFi interface
- **Dynamic Values**: `{interface}` - WiFi interface name from `wifi_interface`
- **Base Model Method(s)**: `mac_address`
- **CLI Commands**: `i` (info)

**`ip route show default | awk '{print $5}'`**
- **Description**: Get network interface used for default internet route
- **Dynamic Values**: None
- **Base Model Method(s)**: `default_interface`
- **CLI Commands**: Internal routing queries

### DNS Management

**`nmcli connection show {connection_name}`**
- **Description**: Get DNS configuration from connection profile (both configured and active DNS)
- **Dynamic Values**: `{connection_name}` - Connection profile name
- **Base Model Method(s)**: `nameservers_from_connection`
- **CLI Commands**: `na` (get nameservers)
- **Notes**: Looks for `ipv4.dns[1]:` entries in output

**`nmcli connection modify {connection_name} ipv4.dns \"{dns_string}\"`**
- **Description**: Set custom DNS servers for connection profile
- **Dynamic Values**: `{connection_name}` - Active WiFi connection profile name, `{dns_string}` - space-separated DNS IPs
- **Base Model Method(s)**: `set_nameservers`
- **CLI Commands**: `na` (set nameservers)

**`nmcli connection modify {connection_name} ipv4.ignore-auto-dns [yes|no]`**
- **Description**: Configure whether to use DNS servers provided by the network
- **Dynamic Values**: `{connection_name}` - Active WiFi connection profile name
- **Base Model Method(s)**: `set_nameservers`
- **CLI Commands**: `na` (set/clear nameservers)
- **Notes**: Set to 'yes' when using custom DNS, 'no' to use automatic DNS

**`nmcli connection modify {connection_name} ipv4.dns \"\"`**
- **Description**: Clear custom DNS servers for connection profile
- **Dynamic Values**: `{connection_name}` - Active WiFi connection profile name
- **Base Model Method(s)**: `set_nameservers` (when clearing)
- **CLI Commands**: `na clear` (clear nameservers)

### DNS Fallback Commands

**`grep \"^nameserver \" /etc/resolv.conf | awk '{print $2}'`**
- **Description**: Get DNS servers from system resolver configuration (fallback method)
- **Dynamic Values**: None
- **Base Model Method(s)**: `nameservers_using_resolv_conf` (private method)
- **CLI Commands**: `na` (get nameservers - fallback when NetworkManager method fails)
- **Notes**: Avoid editing `/etc/resolv.conf` directly; prefer NetworkManager profile modification

### System Integration

**`xdg-open {resource_url}`**
- **Description**: Open URL or file using system default handler
- **Dynamic Values**: `{resource_url}` - URL or file path to open
- **Base Model Method(s)**: `open_resource`
- **CLI Commands**: `ro` (resource open - URLs/files)

### QR Code Generation

**`which qrencode`**
- **Description**: Verify `qrencode` command is available (install: sudo apt install qrencode)
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

### Prerequisite Validation

**`which iw`**
- **Description**: Verify `iw` command is available (install: sudo apt install iw)
- **Dynamic Values**: None
- **Base Model Method(s)**: `validate_os_preconditions`
- **CLI Commands**: All commands (initialization check)

**`which nmcli`**
- **Description**: Verify `nmcli` command is available (install: sudo apt install network-manager)
- **Dynamic Values**: None
- **Base Model Method(s)**: `validate_os_preconditions`
- **CLI Commands**: All commands (initialization check)

### Public IP Information

**`curl -s ipinfo.io`**
- **Description**: Fetches public IP metadata; used only if internet connectivity appears up
- **Dynamic Values**: None
- **Base Model Method(s)**: `BaseModel#public_ip_address_info` (used by `#wifi_info`)
- **CLI Commands**: `i` (info)

### OS Detection

These checks determine whether the current OS matches Ubuntu:

**`cat /etc/os-release` (file read)** and search for `ID=ubuntu`
- **Base OS Method(s)**: `Ubuntu#current_os_is_this_os?`

**`lsb_release -i | grep -q \"Ubuntu\"`**
- **Base OS Method(s)**: `Ubuntu#current_os_is_this_os?`

**`cat /proc/version` (file read)** and search for `Ubuntu`
- **Base OS Method(s)**: `Ubuntu#current_os_is_this_os?`

---

## Ubuntu NetworkManager Concepts

Important Ubuntu-specific concepts for WiFi management:

### Connection Profiles vs SSIDs
NetworkManager stores "connection profiles" which can have any name but connect to a specific SSID. Multiple profiles can exist for the same SSID (e.g., "MySSID", "MySSID 1"). This is a common source of confusion but allows for different configurations per network.

### Profile Selection Logic
When multiple profiles exist for the same SSID, wifi-wand selects the profile with the most recent timestamp (most recently used/configured). This is determined using `nmcli -t -f NAME,TIMESTAMP connection show` and selecting the highest `TIMESTAMP` value.

### Password Management
Passwords are stored per-profile and can differ between profiles connecting to the same network. The system automatically detects security types:
- **WPA/WPA2/WPA3**: Uses `802-11-wireless-security.psk` parameter
- **WEP**: Uses `802-11-wireless-security.wep-key0` parameter
- **Enterprise (802.1x/EAP)**: Intentionally unsupported for PSK-based flows

### Security Parameter Detection
The system uses `nmcli -t -f SSID,SECURITY dev wifi list` to determine the appropriate security parameter when updating passwords or creating connections.

### DNS Configuration
Ubuntu/NetworkManager stores DNS settings per connection profile. Always modify DNS through NetworkManager (`nmcli connection modify`) rather than editing `/etc/resolv.conf` directly, as NetworkManager will overwrite manual changes.

### Error Handling
The system handles specific NetworkManager exit codes gracefully:
- Exit code 6 (device not active): Treated as non-error for disconnect operations
- Connection timeouts and failures are mapped to user-friendly error messages

### Profile Naming Patterns
NetworkManager often creates profiles with names that start with the SSID but may include suffixes (e.g., "MyNetwork 1"). The code handles this by finding profiles whose names start with the target SSID and selecting the most recent by timestamp.
