# macOS OS Command Use
### os-command-use-mac-gemini.md
### 2025-08-26 12:00:00 UTC

This document outlines the shell commands used by `wifi-wand` on the macOS operating system.

## `networksetup`

`networksetup` is the primary command-line tool for configuring network settings in macOS.

### `networksetup -listallhardwareports`

*   **Description:** Lists all hardware ports to find the name of the Wi-Fi service (e.g., "Wi-Fi", "AirPort").
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `detect_wifi_service_name`, `detect_wifi_interface_using_networksetup`
*   **CLI Command(s):** (Internal use)

### `networksetup -listpreferredwirelessnetworks <interface>`

*   **Description:** Lists the preferred (saved) wireless networks for a given interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `preferred_networks`
*   **CLI Command(s):** `pr` (preferred networks)

### `networksetup -getairportpower <interface>`

*   **Description:** Checks if the Wi-Fi radio for the specified interface is on.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `wifi_on?`
*   **CLI Command(s):** `w` (status)

### `networksetup -setairportpower <interface> on`

*   **Description:** Turns the Wi-Fi radio on for the specified interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `wifi_on`
*   **CLI Command(s):** `on`

### `networksetup -setairportpower <interface> off`

*   **Description:** Turns the Wi-Fi radio off for the specified interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `wifi_off`
*   **CLI Command(s):** `of`

### `networksetup -setairportnetwork <interface> <network_name> [password]`

*   **Description:** Connects to a Wi-Fi network. This is a fallback method.
*   **Dynamic Values:** `interface`, `network_name`, `password`
*   **Base Model Method(s):** `os_level_connect_using_networksetup`
*   **CLI Command(s):** `co` (connect)

### `sudo networksetup -removepreferredwirelessnetwork <interface> <network_name>`

*   **Description:** Removes a network from the preferred networks list.
*   **Dynamic Values:** `interface`, `network_name`
*   **Base Model Method(s):** `remove_preferred_network`
*   **CLI Command(s):** `f` (forget)

### `networksetup -setdnsservers <service_name> <dns_servers|empty>`

*   **Description:** Sets or clears the DNS servers for a given network service.
*   **Dynamic Values:** `service_name`, `dns_servers`
*   **Base Model Method(s):** `set_nameservers`
*   **CLI Command(s):** `na` (nameservers)

### `networksetup -getdnsservers <service_name>`

*   **Description:** Gets the currently configured DNS servers for a network service.
*   **Dynamic Values:** `service_name`
*   **Base Model Method(s):** `nameservers_using_networksetup`
*   **CLI Command(s):** `na` (nameservers)

## `system_profiler`

`system_profiler` provides detailed reports about the system's hardware and software.

### `system_profiler -json SPNetworkDataType`

*   **Description:** Gets detailed network information in JSON format to detect the Wi-Fi interface name (e.g., en0).
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `detect_wifi_interface`
*   **CLI Command(s):** (Internal use)

### `system_profiler -json SPAirPortDataType`

*   **Description:** Gets detailed Wi-Fi information, including available networks and the current connection.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_available_network_names`, `_connected_network_name`
*   **CLI Command(s):** `a` (available networks), `ne` (network name)

## `security`

The `security` command provides tools for managing keys, certificates, and passwords in the keychain.

### `security find-generic-password -D "AirPort network password" -a <network_name> -w`

*   **Description:** Retrieves the stored password for a preferred Wi-Fi network from the keychain.
*   **Dynamic Values:** `network_name`
*   **Base Model Method(s):** `_preferred_network_password`
*   **CLI Command(s):** `pa` (password)

## `ifconfig`

`ifconfig` is used for network interface configuration.

### `ipconfig getifaddr <interface>`

*   **Description:** Gets the IP address for the specified interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `_ip_address`
*   **CLI Command(s):** `i` (info)

### `ifconfig <interface> | awk '/ether/{print $2}'`

*   **Description:** Gets the MAC address for the specified interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `mac_address`
*   **CLI Command(s):** `i` (info)

### `sudo ifconfig <interface> disassociate`

*   **Description:** Disconnects from the current Wi-Fi network. This is a fallback method.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `_disconnect`
*   **CLI Command(s):** `d` (disconnect)

## `swift`

`swift` is used to execute Swift code for more modern macOS interactions.

### `swift WifiNetworkConnector.swift <network_name> [password]`

*   **Description:** Connects to a Wi-Fi network using a Swift script that leverages the CoreWLAN framework.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method(s):** `os_level_connect_using_swift`
*   **CLI Command(s):** `co` (connect)

### `swift WifiNetworkDisconnector.swift`

*   **Description:** Disconnects from the current Wi-Fi network using a Swift script.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_disconnect`
*   **CLI Command(s):** `d` (disconnect)

## Other Commands

### `open -a <application_name>`

*   **Description:** Opens a specified application.
*   **Dynamic Values:** `application_name`
*   **Base Model Method(s):** `open_application`
*   **CLI Command(s):** `ro` (open resource)

### `open <resource_url>`

*   **Description:** Opens a URL in the default web browser.
*   **Dynamic Values:** `resource_url`
*   **Base Model Method(s):** `open_resource`
*   **CLI Command(s):** `ro` (open resource)

### `scutil --dns`

*   **Description:** Retrieves DNS information from the System Configuration framework.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `nameservers_using_scutil`
*   **CLI Command(s):** `na` (nameservers)

### `route -n get default | grep 'interface:' | awk '{print $2}'`

*   **Description:** Determines the default network interface used for internet traffic.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `default_interface`
*   **CLI Command(s):** `i` (info)

### `sw_vers -productVersion`

*   **Description:** Detects the current macOS version.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `detect_macos_version`
*   **CLI Command(s):** (Internal use)
