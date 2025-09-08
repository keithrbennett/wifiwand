# OS Command Usage for macOS

### os-command-use-mac-gemini.md

### 2025-09-09T21:22:00Z

This document details the shell commands used by `wifi-wand` on the macOS operating system.

## Network Management on macOS

On macOS, `wifi-wand` uses a variety of tools to manage network settings. The primary tool is `networksetup`, but it also uses `system_profiler` for detailed information, `security` for keychain access, and `ifconfig` for some interface-level actions. For connecting and disconnecting, it prefers to use a modern Swift-based helper utility that interacts with the CoreWLAN framework directly.

- **`networksetup`**: A versatile command for configuring network services, including Wi-Fi power, preferred networks, and DNS settings.
- **`system_profiler`**: Provides detailed hardware and software information in JSON format. It is used to get a comprehensive list of available networks and their properties, though it can be slower than other methods.
- **`security`**: The command-line interface to the macOS Keychain. It is used to securely retrieve stored Wi-Fi passwords.
- **Swift Helpers**: Custom Swift scripts (`WifiNetworkConnector`, `WifiNetworkDisconnector`) are used for a more reliable and modern connection and disconnection experience.

---

## `networksetup`

### `networksetup -listallhardwareports`

*   **Description:** Lists all hardware ports to dynamically detect the name of the Wi-Fi service (e.g., "Wi-Fi" or "AirPort").
*   **Dynamic Values:** None.
*   **Base Model Method:** `detect_wifi_service_name`
*   **CLI Commands:** All (during initialization).

### `networksetup -listpreferredwirelessnetworks <interface>`

*   **Description:** Lists the preferred (saved) wireless networks for a given interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method:** `preferred_networks`
*   **CLI Commands:** `pr`, `f`

### `networksetup -getairportpower <interface>`

*   **Description:** Checks if the Wi-Fi radio is currently powered on.
*   **Dynamic Values:** `interface`
*   **Base Model Method:** `wifi_on?`
*   **CLI Commands:** `w`, `i`, `a`, `s`, `cy`

### `networksetup -setairportpower <interface> [on|off]`

*   **Description:** Turns the Wi-Fi radio on or off.
*   **Dynamic Values:** `interface`, `on` or `off`.
*   **Base Model Methods:** `wifi_on`, `wifi_off`
*   **CLI Commands:** `on`, `of`, `cy`

### `networksetup -setairportnetwork <interface> <network> [password]`

*   **Description:** (Fallback Method) Connects to a Wi-Fi network.
*   **Dynamic Values:** `interface`, `network`, `password`.
*   **Base Model Method:** `_connect` (via `os_level_connect_using_networksetup`)
*   **CLI Commands:** `co`

### `sudo networksetup -removepreferredwirelessnetwork <interface> <network>`

*   **Description:** Removes a network from the list of preferred networks. Requires `sudo`.
*   **Dynamic Values:** `interface`, `network`.
*   **Base Model Method:** `remove_preferred_network`
*   **CLI Commands:** `f`

### `networksetup -setdnsservers <service> [servers|empty]`

*   **Description:** Sets or clears the DNS servers for a network service.
*   **Dynamic Values:** `service`, DNS server IPs.
*   **Base Model Method:** `set_nameservers`
*   **CLI Commands:** `na`

### `networksetup -getdnsservers <service>`

*   **Description:** Retrieves the configured DNS servers for a service.
*   **Dynamic Values:** `service`.
*   **Base Model Method:** `nameservers_using_networksetup`
*   **CLI Commands:** `na` (as a fallback)

---

## `system_profiler`

### `system_profiler -json SPNetworkDataType`

*   **Description:** Gathers detailed information about all network interfaces.
*   **Dynamic Values:** None.
*   **Base Model Method:** `detect_wifi_interface`
*   **CLI Commands:** All (during initialization).

### `system_profiler -json SPAirPortDataType`

*   **Description:** Gathers detailed Wi-Fi information, including available and connected networks.
*   **Dynamic Values:** None.
*   **Base Model Methods:** `_available_network_names`, `_connected_network_name`, `connection_security_type`
*   **CLI Commands:** `a`, `ne`, `i`, `s`, `qr`

---

## `security`

### `security find-generic-password -D "AirPort network password" -a <network> -w`

*   **Description:** Retrieves a stored Wi-Fi password from the user's Keychain.
*   **Dynamic Values:** `network`.
*   **Base Model Method:** `_preferred_network_password`
*   **CLI Commands:** `pa`, `qr` (indirectly)

---

## Swift Helpers

### `swift WifiNetworkConnector.swift <network> [password]`

*   **Description:** (Primary Method) Connects to a Wi-Fi network using the CoreWLAN framework.
*   **Dynamic Values:** `network`, `password`.
*   **Base Model Method:** `_connect` (via `os_level_connect_using_swift`)
*   **CLI Commands:** `co`

### `swift WifiNetworkDisconnector.swift`

*   **Description:** (Primary Method) Disconnects from the current Wi-Fi network.
*   **Dynamic Values:** None.
*   **Base Model Method:** `_disconnect`
*   **CLI Commands:** `d`

### `swift -e 'import CoreWLAN'`

*   **Description:** Checks if Swift and the CoreWLAN framework are available.
*   **Dynamic Values:** None.
*   **Base Model Method:** `swift_and_corewlan_present?`
*   **CLI Commands:** `co`, `d` (to determine connection/disconnection strategy)

---

## Other Commands

### `ipconfig getifaddr <interface>`

*   **Description:** Gets the IP address for a given interface.
*   **Dynamic Values:** `interface`.
*   **Base Model Method:** `_ip_address`
*   **CLI Commands:** `i`

### `ifconfig <interface> | awk '/ether/{print $2}'`

*   **Description:** Gets the MAC address for an interface.
*   **Dynamic Values:** `interface`.
*   **Base Model Method:** `mac_address`
*   **CLI Commands:** `i`

### `[sudo] ifconfig <interface> disassociate`

*   **Description:** (Fallback Method) Disconnects the interface from its current network.
*   **Dynamic Values:** `interface`.
*   **Base Model Method:** `_disconnect`
*   **CLI Commands:** `d`

### `scutil --dns`

*   **Description:** (Primary Method) Retrieves the system's current DNS configuration.
*   **Dynamic Values:** None.
*   **Base Model Method:** `nameservers_using_scutil`
*   **CLI Commands:** `na`

### `open [-a <application>|<resource_url>]`

*   **Description:** Opens an application or a URL/file.
*   **Dynamic Values:** `application_name`, `resource_url`.
*   **Base Model Methods:** `open_application`, `open_resource`
*   **CLI Commands:** `ro`

### `route -n get default | ...`

*   **Description:** Finds the network interface for the default route.
*   **Dynamic Values:** None.
*   **Base Model Method:** `default_interface`
*   **CLI Commands:** `i`

### `sw_vers -productVersion`

*   **Description:** Detects the current macOS version number.
*   **Dynamic Values:** None.
*   **Base Model Method:** `detect_macos_version`
*   **CLI Commands:** All (during initialization).