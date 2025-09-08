# macOS OS Command Use
### os-command-use-mac-openai.md
### 2025-09-08 00:00:00 UTC

This document outlines the shell commands used by `wifi-wand` on the macOS operating system.

Notes:
- macOS distinguishes between network service names (e.g., "Wi‑Fi") and device interfaces (e.g., `en0`). Many `networksetup` subcommands take a service name, while others take an interface device. This project detects the Wi‑Fi service name dynamically and uses the appropriate value for each command.

## `networksetup`

`networksetup` is the primary command-line tool for configuring network settings in macOS.

### `networksetup -listallhardwareports`
- Description: Lists all hardware ports to locate the Wi‑Fi service name (e.g., "Wi‑Fi", "AirPort").
- Dynamic Values: None
- Base Model Method(s): `detect_wifi_service_name`, `detect_wifi_interface_using_networksetup`
- CLI Command(s): Internal (interface/service detection)

### `networksetup -listpreferredwirelessnetworks <interface>`
- Description: Lists the preferred (saved) wireless networks for a given interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `preferred_networks`
- CLI Command(s): `pr` (preferred networks)

### `networksetup -getairportpower <interface>`
- Description: Checks if Wi‑Fi radio is on for the specified interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_on?`
- CLI Command(s): `w` (wifi status)

### `networksetup -setairportpower <interface> on`
- Description: Turns Wi‑Fi radio on for the specified interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_on`
- CLI Command(s): `on`

### `networksetup -setairportpower <interface> off`
- Description: Turns Wi‑Fi radio off for the specified interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_off`
- CLI Command(s): `of`

### `networksetup -setairportnetwork <interface> <network_name> [password]`
- Description: Connects to a Wi‑Fi network using Network Setup (fallback path when Swift/CoreWLAN is unavailable).
- Dynamic Values: `interface`, `network_name`, `password`
- Base Model Method(s): `os_level_connect_using_networksetup`, `_connect`
- CLI Command(s): `co` (connect)

### `sudo networksetup -removepreferredwirelessnetwork <interface> <network_name>`
- Description: Removes a network from the preferred networks list.
- Dynamic Values: `interface`, `network_name`
- Base Model Method(s): `remove_preferred_network`
- CLI Command(s): `f` (forget)

### `networksetup -setdnsservers <service_name> <dns_servers|empty>`
- Description: Sets custom DNS servers for the Wi‑Fi service, or clears them with `empty`.
- Dynamic Values: `service_name` (from detected Wi‑Fi service), `dns_servers` (space-separated IPv4 addresses)
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na` (nameservers)

### `networksetup -getdnsservers <service_name>`
- Description: Gets configured DNS servers for the Wi‑Fi service.
- Dynamic Values: `service_name`
- Base Model Method(s): `nameservers_using_networksetup`
- CLI Command(s): `na` (nameservers)

## `system_profiler`

`system_profiler` provides detailed reports about the system.

### `system_profiler -json SPNetworkDataType`
- Description: Gets network data in JSON to detect the Wi‑Fi interface (e.g., `en0`).
- Dynamic Values: None
- Base Model Method(s): `detect_wifi_interface`
- CLI Command(s): Internal (interface detection)

### `system_profiler -json SPAirPortDataType`
- Description: Gets Wi‑Fi details (available networks, current connection, security info).
- Dynamic Values: None
- Base Model Method(s): `_available_network_names`, `_connected_network_name`, `connection_security_type`, `airport_data`
- CLI Command(s): `a` (available networks), `ne` (network name), `i` (info)

## `security` (Keychain)

### `security find-generic-password -D "AirPort network password" -a <network_name> -w`
- Description: Retrieves stored password for a preferred Wi‑Fi network from the login keychain.
- Dynamic Values: `network_name`
- Base Model Method(s): `_preferred_network_password`
- CLI Command(s): `pa` (password)
- Helpful Info: Exit codes are mapped to specific keychain errors (e.g., 44 item not found, 45 access denied).

## IP, Interface, and Disconnect

### `ipconfig getifaddr <interface>`
- Description: Gets the IP address for the specified interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `_ip_address`
- CLI Command(s): `i` (info)

### `ifconfig <interface> | awk '/ether/{print $2}'`
- Description: Gets the MAC address for the specified interface.
- Dynamic Values: `interface`
- Base Model Method(s): `mac_address`
- CLI Command(s): `i` (info)

### `sudo ifconfig <interface> disassociate` (fallback; then `ifconfig <interface> disassociate`)
- Description: Disassociates from the current Wi‑Fi network when Swift/CoreWLAN disconnect is unavailable.
- Dynamic Values: `interface`
- Base Model Method(s): `_disconnect`
- CLI Command(s): `d` (disconnect)

## Swift and CoreWLAN

### `swift -e 'import CoreWLAN'`
- Description: Checks Swift/CoreWLAN availability for enhanced Wi‑Fi control.
- Dynamic Values: None
- Base Model Method(s): `swift_and_corewlan_present?`
- CLI Command(s): Internal capability check

### `swift swift/WifiNetworkConnector.swift <network_name> [password]`
- Description: Connects to Wi‑Fi using Swift + CoreWLAN when available.
- Dynamic Values: `network_name`, `password`
- Base Model Method(s): `os_level_connect_using_swift`, `_connect`
- CLI Command(s): `co` (connect)

### `swift swift/WifiNetworkDisconnector.swift`
- Description: Disconnects from Wi‑Fi using Swift + CoreWLAN when available.
- Dynamic Values: None
- Base Model Method(s): `_disconnect`
- CLI Command(s): `d` (disconnect)

## DNS Inspection

### `scutil --dns`
- Description: Retrieves DNS configuration from the System Configuration framework (scoped and unscoped). Preferred for accurate DNS on macOS.
- Dynamic Values: None
- Base Model Method(s): `nameservers_using_scutil`, `nameservers`
- CLI Command(s): `na` (nameservers)

## Routing and OS Version

### `route -n get default | grep 'interface:' | awk '{print $2}'`
- Description: Determines the default network interface used for internet traffic.
- Dynamic Values: None
- Base Model Method(s): `default_interface`
- CLI Command(s): `i` (info)

### `sw_vers -productVersion`
- Description: Detects current macOS version for compatibility checks.
- Dynamic Values: None
- Base Model Method(s): `detect_macos_version`, `validate_macos_version`
- CLI Command(s): Internal

## App/URL Open

### `open -a <application_name>`
- Description: Opens an application by name.
- Dynamic Values: `application_name`
- Base Model Method(s): `open_application`
- CLI Command(s): `ro` (open resource)

### `open <resource_url>`
- Description: Opens a URL or file with the default handler.
- Dynamic Values: `resource_url`
- Base Model Method(s): `open_resource`
- CLI Command(s): `ro` (open resource)

## QR Code Generation

Requires `qrencode` to be installed (e.g., `brew install qrencode`).

### `qrencode -o <file> <wifi_qr_string>`
- Description: Writes a QR image file (PNG default; use `-t SVG` or `-t EPS` for other types).
- Dynamic Values: `file` (default: `<SSID>-qr-code.png`), `wifi_qr_string` (built from SSID/security/password)
- Base Model Method(s): `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_file!`
- CLI Command(s): `qr [filespec]`

### `qrencode -t ANSI <wifi_qr_string>`
- Description: Prints an ANSI QR code to stdout when filespec is `-`.
- Dynamic Values: `wifi_qr_string`
- Base Model Method(s): `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_text!`
- CLI Command(s): `qr -`

### `which qrencode`
- Description: Checked to ensure `qrencode` is available; suggests Homebrew install if missing.
- Dynamic Values: None
- Base Model Method(s): `Helpers::QrCodeGenerator#ensure_qrencode_available!`
- CLI Command(s): `qr` (pre-check)

## Public IP Info (Info Command)

### `curl -s ipinfo.io`
- Description: Fetches public IP metadata; used only when connectivity appears up.
- Dynamic Values: None
- Base Model Method(s): `BaseModel#public_ip_address_info` (used by `#wifi_info`)
- CLI Command(s): `i` (info)

