# Ubuntu OS Command Usage

### os-command-use-ubuntu-gemini.md

### Mon Oct 20 00:00:00 PM UTC 2025

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

**`nmcli radio wifi on`**
- Description: Enables WiFi radio
- Dynamic values: None
- Base model method(s): `wifi_on`
- CLI commands: `on` (enable wifi)

**`nmcli radio wifi off`**
- Description: Disables WiFi radio
- Dynamic values: None
- Base model method(s): `wifi_off`
- CLI commands: `of` (disable wifi)

### Network Discovery

**`nmcli -t -f SSID,SIGNAL dev wifi list`**
- Description: Lists available networks with signal strength, sorted by signal strength
- Dynamic values: None
- Base model method(s): `_available_network_names`
- CLI commands: `a` (available networks)

**`nmcli -t -f SSID,SECURITY dev wifi list`**
- Description: Get security type (WPA2, WPA3, WEP, etc.) for all available networks
- Dynamic values: None
- Base model method(s): `get_security_parameter`, `security_parameter`, `connection_security_type`
- CLI commands: `co` (connect - for determining security type), internal security checks

### Connection Status

**`nmcli -t -f active,ssid device wifi`**
- Description: Get SSID of currently connected network (returns SSID, not connection profile name)
- Dynamic values: None
- Base model method(s): `_connected_network_name`
- CLI commands: `ne` (network name), `i` (info), status checks

### Network Connection

**`nmcli dev wifi connect {network_name}`**
- Description: Connect to open network or create new connection profile
- Dynamic values: `{network_name}` - SSID to connect to
- Base model method(s): `connect_with_wifi_command` (private method)
- CLI commands: `co` (connect)

**`nmcli dev wifi connect {network_name} password {password}`**
- Description: Connect to secured network with password
- Dynamic values: `{network_name}` - SSID to connect to, `{password}` - network password
- Base model method(s): `connect_with_wifi_command` (private method)
- CLI commands: `co` (connect with password)

**`nmcli connection up {profile}`**
- Description: Activate existing connection profile by name
- Dynamic values: `{profile}` - Connection profile name (often same as SSID)
- Base model method(s): `_connect`, `connect_with_wifi_command`
- CLI commands: `co` (connect using existing profile)

**`nmcli connection modify {profile} {security_param} {password}`**
- Description: Update password in existing connection profile
- Dynamic values: `{profile}` - Connection profile name, `{security_param}` (`802-11-wireless-security.psk` or `802-11-wireless-security.wep-key0`), `{password}` - new password
- Base model method(s): `_connect` (private method, via `get_security_parameter`)
- CLI commands: `co` (connect - update existing profile password)

### Connection Management

**`nmcli -t -f NAME connection show`**
- Description: List all saved connection profiles (NetworkManager profiles, not just SSIDs)
- Dynamic values: None
- Base model method(s): `preferred_networks`
- CLI commands: `pr` (preferred networks)

**`nmcli -t -f- NAME,TIMESTAMP connection show`**
- Description: List connection profiles with timestamps to find most recently used
- Dynamic values: None
- Base model method(s): `find_best_profile_for_ssid` (private method)
- CLI commands: `co` (connect - profile selection logic)

**`nmcli connection delete {network_name}`**
- Description: Delete a stored connection profile
- Dynamic values: `{network_name}` - Connection profile name to delete
- Base model method(s): `remove_preferred_network`
- CLI commands: `f` (forget network)

**`nmcli dev disconnect {interface}`**
- Description: Disconnect from current network
- Dynamic values: `{interface}` - WiFi interface name from `wifi_interface`
- Base model method(s): `_disconnect`
- CLI commands: `d` (disconnect)

### Password Retrieval

**`nmcli --show-secrets connection show {preferred_network_name}`**
- Description: Retrieve stored password for a connection profile
- Dynamic values: `{preferred_network_name}` - Connection profile name
- Base model method(s): `_preferred_network_password`
- CLI commands: `pa` (password for preferred network)

### Network Information

**`ip -4 addr show {wifi_interface}`**
- Description: Get IPv4 address of WiFi interface
- Dynamic values: `{wifi_interface}` - WiFi interface name
- Base model method(s): `_ip_address`
- CLI commands: `i` (info)

**`ip link show {wifi_interface}`**
- Description:- You are a senior software architect and code reviewer.
- Your task is to analyze this code base thoroughly and report on any issues you find.
- Focus on identifying errors, weaknesses, risks, and areas for improvement.
- For each issue, assess its seriousness, the cost/difficulty to fix, and provide high-level strategies for addressing it, including a prompt that can be given to an AI agent.
- Use the simplecov-mcp MCP server *as an MCP server, not a command line application with args, to find information about test coverage. Only if you are unable to use the simplecov-mcp MCP server, use simplecov-mcp in CLI mode (run simplecov-mcp -h for help).
- Write your analysis in a Markdown file whose name is:

today's date in YYYY-MM-DD format +
'-action-items-' +
your name (e.g. 'codex, claude, gemini, zai)

At the end, produce a markdown table that summarizes the issues, in descending order of importance, including as columns:

- brief description (preferably <= 50 chars)
- importance rating (10 to 1)
- effort rating (1 to 10)
- link to detail for that item

Do not report:

* Low Test Coverage in OS code for OS's other than the current one.


**DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**

 Get MAC address of WiFi interface
- Dynamic values: `{wifi_interface}` - WiFi interface name
- Base model method(s): `mac_address`
- CLI commands: `i` (info)

**`ip route show default`**
- Description: Get network interface used for default internet route
- Dynamic values: None
- Base model method(s): `default_interface`
- CLI commands: Internal routing queries

**`nmcli -t -f GENERAL.CONNECTION dev show {interface}`**
- Description: Get the name of the active connection profile for an interface.
- Dynamic values: `{interface}` - The network interface.
- Base model method(s): `_current_connection_name`
- CLI commands: `na` (nameservers)

### DNS Management

**`nmcli connection modify {current_connection} ipv4.dns ''`**
- Description: Clear custom DNS servers for connection profile
- Dynamic values: `{current_connection}` - Active WiFi connection profile name
- Base model method(s): `set_nameservers` (when clearing)
- CLI commands: `na clear` (clear nameservers)

**`nmcli connection modify {current_connection} ipv4.ignore-auto-dns no`**
- Description: Re-enable automatic DNS from router/DHCP
- Dynamic values: `{current_connection}` - Active WiFi connection profile name
- Base model method(s): `set_nameservers` (when clearing)
- CLI commands: `na clear` (restore automatic DNS)

**`nmcli connection modify {current_connection} ipv4.dns {dns_string}`**
- Description: Set custom DNS servers for connection profile
- Dynamic values: `{current_connection}` - Active WiFi connection profile name, `{dns_string}` - space-separated DNS IPs
- Base model method(s): `set_nameservers`
- CLI commands: `na` (set nameservers)

**`nmcli connection modify {current_connection} ipv4.ignore-auto-dns yes`**
- Description: Disable automatic DNS from router/DHCP when using custom DNS
- Dynamic values: `{current_connection}` - Active WiFi connection profile name
- Base model method(s): `set_nameservers` (with custom DNS)
- CLI commands: `na` (set nameservers)

**`nmcli connection up {current_connection}`**
- Description: Restart connection to apply DNS changes
- Dynamic values: `{current_connection}` - Active WiFi connection profile name
- Base model method(s): `set_nameservers` (after DNS changes)
- CLI commands: `na` (apply DNS changes)

**`nmcli connection show {connection_name}`**
- Description: Get DNS configuration from connection profile (both configured and active DNS)
- Dynamic values: `{connection_name}` - Connection profile name
- Base model method(s): `nameservers_from_connection`
- CLI commands: `na` (get nameservers)

### System Integration

**`xdg-open {resource_url}`**
- Description: Open URL or file using system default handler
- Dynamic values: `{resource_url}` - URL or file path to open
- Base model method(s): `open_resource`
- CLI commands: `ro` (resource open - URLs/files)

### QR Code Generation

**`which qrencode`**
- Description: Verify `qrencode` command is available (install: sudo apt install qrencode)
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
