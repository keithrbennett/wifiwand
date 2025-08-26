# Ubuntu OS Command Usage

### os-command-use-ubuntu-claude.md

### Tue Aug 26 01:36:12 PM UTC 2025

Ubuntu WiFi management uses NetworkManager (`nmcli`) for connection management and profiles, and `iw` and `ip` for lower-level interface operations. **Key concept**: NetworkManager maintains connection profiles (stored configurations) which are separate from SSIDs. A profile can have any name and connects to a specific SSID.

## Command Usage by Category

### WiFi Interface Detection

**`iw dev | grep Interface | cut -d' ' -f2`**
- Finds the first WiFi interface name
- Dynamic values: None
- Base model method(s): `detect_wifi_interface`
- CLI commands: All WiFi operations (automatic interface detection)

**`iw dev {interface} info 2>/dev/null`**
- Validates if an interface is WiFi-capable
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `is_wifi_interface?`
- CLI commands: Interface validation (internal)

### Radio Control

**`nmcli radio wifi`**
- Check if WiFi radio is enabled (returns 'enabled' or 'disabled')
- Dynamic values: None
- Base model method(s): `wifi_on?`
- CLI commands: `w` (wifi status), and internal checks in most WiFi operations

**`nmcli radio wifi on`
- Description: Enables WiFi radio
- Dynamic values: None
- Base model method(s): `wifi_on`
- CLI commands: `on` (enable wifi)

**`nmcli radio wifi off`
- Description: Disables WiFi radio
- Dynamic values: None
- Base model method(s): `wifi_off`
- CLI commands: `of` (disable wifi)

### Network Discovery

**`nmcli -t -f SSID,SIGNAL dev wifi list`
- Description: Lists available networks with signal strength, sorted by signal strength
- Dynamic values: None
- Base model method(s): `_available_network_names`
- CLI commands: `a` (available networks)

**`nmcli dev wifi list | grep {ssid}`
- Description: Get security type (WPA2, WPA3, WEP, etc.) for a specific SSID
- Dynamic values: `{ssid}` - Network SSID from method parameter
- Base model method(s): `get_security_type` (private method in `_connect`)
- CLI commands: `co` (connect - for determining security type)

### Connection Status

**`nmcli -t -f active,ssid device wifi | egrep '^yes' | cut -d\: -f2`
- Description: Get SSID of currently connected network (returns SSID, not connection profile name)
- Dynamic values: None
- Base model method(s): `_connected_network_name`
- CLI commands: `ne` (network name), `i` (info), status checks

### Network Connection

**`nmcli dev wifi connect {network_name}`
- Description: Connect to open network or create new connection profile
- Dynamic values: `{network_name}` - SSID to connect to
- Base model method(s): `connect_with_wifi_command` (private method)
- CLI commands: `co` (connect)

**`nmcli dev wifi connect {network_name} password {password}`
- Description: Connect to secured network with password
- Dynamic values: `{network_name}` - SSID to connect to, `{password}` - network password
- Base model method(s): `connect_with_wifi_command` (private method)
- CLI commands: `co` (connect with password)

**`nmcli connection up {network_name}`
- Description: Activate existing connection profile by name
- Dynamic values: `{network_name}` - Connection profile name (often same as SSID)
- Base model method(s): `_connect`, `connect_with_wifi_command`
- CLI commands: `co` (connect using existing profile)

**`nmcli connection modify {network_name} 802-11-wireless-security.psk {password}`
- Description: Update stored password in existing connection profile
- Dynamic values: `{network_name}` - Connection profile name, `{password}` - new password
- Base model method(s): `connect_with_wifi_command` (private method)
- CLI commands: `co` (connect - update existing profile password)

### Connection Management

**`nmcli -t -f NAME connection show`
- Description: List all saved connection profiles (NetworkManager profiles, not just SSIDs)
- Dynamic values: None
- Base model method(s): `preferred_networks`
- CLI commands: `pr` (preferred networks)

**`nmcli connection delete {network_name}`
- Description: Delete a stored connection profile
- Dynamic values: `{network_name}` - Connection profile name to delete
- Base model method(s): `remove_preferred_network`
- CLI commands: `f` (forget network)

**`nmcli dev disconnect {interface}`
- Description: Disconnect from current network
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_disconnect`
- CLI commands: `d` (disconnect)

### Password Retrieval

**`nmcli --show-secrets connection show {network_name} | grep '802-11-wireless-security.psk:' | cut -d':' -f2-`
- Description: Retrieve stored password for a connection profile
- Dynamic values: `{network_name}` - Connection profile name
- Base model method(s): `_preferred_network_password`
- CLI commands: `pa` (password for preferred network)

### Network Information

**`ip -4 addr show {interface} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1`
- Description: Get IPv4 address of WiFi interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_ip_address`
- CLI commands: `i` (info)

**`ip link show {interface} | grep ether | awk '{print $2}'`
- Description: Get MAC address of WiFi interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `mac_address`
- CLI commands: `i` (info)

**`ip route show default | awk '{print $5}'`
- Description: Get network interface used for default internet route
- Dynamic values: None
- Base model method(s): `default_interface`
- CLI commands: Internal routing queries

### DNS Management

**`nmcli connection modify {interface} ipv4.dns ""`
- Description: Clear custom DNS servers for interface
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `set_nameservers` (when clearing)
- CLI commands: `na clear` (clear nameservers)

**`nmcli connection modify {interface} ipv4.dns {dns_string}`
- Description: Set custom DNS servers for interface
- Dynamic values: `{interface}` - WiFi interface name, `{dns_string}` - space-separated DNS IPs
- Base model method(s): `set_nameservers`
- CLI commands: `na` (set nameservers)

**`nmcli connection up {interface}`
- Description: Restart connection to apply DNS changes
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `set_nameservers` (after DNS changes)
- CLI commands: `na` (apply DNS changes)

### System Integration

**`xdg-open {application_name}`
- Description: Open application using system default handler
- Dynamic values: `{application_name}` - Application name or path
- Base model method(s): `open_application`
- CLI commands: `ro` (resource open - applications)

**`xdg-open {resource_url}`
- Description: Open URL or file using system default handler
- Dynamic values: `{resource_url}` - URL or file path to open
- Base model method(s): `open_resource`
- CLI commands: `ro` (resource open - URLs/files)

### Prerequisite Validation

**`which iw`
- Description: Verify `iw` command is available
- Dynamic values: None
- Base model method(s): `validate_os_preconditions`
- CLI commands: All commands (initialization check)

**`which nmcli`
- Description: Verify `nmcli` command is available (NetworkManager)
- Dynamic values: None
- Base model method(s): `validate_os_preconditions`
- CLI commands: All commands (initialization check)