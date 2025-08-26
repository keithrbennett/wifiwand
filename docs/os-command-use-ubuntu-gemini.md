# Ubuntu OS Command Use
### os-command-use-ubuntu-gemini.md
### 2025-08-26 12:00:00 UTC

This document outlines the shell commands used by `wifi-wand` on the Ubuntu operating system.

## `nmcli` - NetworkManager Command Line Interface

`nmcli` is the primary tool used for managing network connections on Ubuntu. It interacts with NetworkManager to control Wi-Fi adapters, scan for networks, and manage connection profiles.

### `nmcli radio wifi`

*   **Description:** Checks if the Wi-Fi radio is enabled.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_on?`
*   **CLI Command(s):** `w` (status)

### `nmcli radio wifi on`

*   **Description:** Turns the Wi-Fi radio on.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_on`
*   **CLI Command(s):** `on`

### `nmcli radio wifi off`

*   **Description:** Turns the Wi-Fi radio off.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_off`
*   **CLI Command(s):** `of`

### `nmcli -t -f SSID,SIGNAL dev wifi list`

*   **Description:** Lists available Wi-Fi networks with their signal strength.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_available_network_names`
*   **CLI Command(s):** `a` (available networks)

### `nmcli -t -f active,ssid device wifi | egrep '^yes' | cut -d\: -f2`

*   **Description:** Shows the SSID of the currently active Wi-Fi connection.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_connected_network_name`
*   **CLI Command(s):** `ne` (network name)

### `nmcli dev wifi list | grep <ssid>`

*   **Description:** Retrieves the full details of a specific network from the scan list to determine its security type.
*   **Dynamic Values:** `ssid`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli connection up <network_name>`

*   **Description:** Activates an existing NetworkManager connection profile.
*   **Dynamic Values:** `network_name`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli -t -f NAME connection show`

*   **Description:** Lists the names of all saved NetworkManager connection profiles.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `preferred_networks`
*   **CLI Command(s):** `pr` (preferred networks), `co` (connect)

### `nmcli connection modify <network_name> 802-11-wireless-security.psk <password>`

*   **Description:** Sets the password for a WPA-secured network on an existing connection profile.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli dev wifi connect <network_name> password <password>`

*   **Description:** Connects to a Wi-Fi network, creating a new profile if one doesn't exist.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli connection delete <network_name>`

*   **Description:** Deletes a NetworkManager connection profile.
*   **Dynamic Values:** `network_name`
*   **Base Model Method(s):** `remove_preferred_network`
*   **CLI Command(s):** `f` (forget)

### `nmcli --show-secrets connection show <network_name> | grep '802-11-wireless-security.psk:' | cut -d':' -f2-`

*   **Description:** Shows the Wi-Fi password for a saved connection profile.
*   **Dynamic Values:** `preferred_network_name`
*   **Base Model Method(s):** `_preferred_network_password`
*   **CLI Command(s):** `pa` (password)

### `nmcli dev disconnect <interface>`

*   **Description:** Disconnects a specific network interface from any active connection.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `_disconnect`
*   **CLI Command(s):** `d` (disconnect)

### `nmcli connection modify <interface> ipv4.dns "<dns_servers>"`

*   **Description:** Sets the DNS servers for a network connection.
*   **Dynamic Values:** `interface`, `dns_servers`
*   **Base Model Method(s):** `set_nameservers`
*   **CLI Command(s):** `na` (nameservers)

## `ip` - IP Command

The `ip` command is used to show and manipulate routing, devices, policy routing and tunnels.

### `ip -4 addr show <interface> | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1`

*   **Description:** Shows the IPv4 address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface`
*   **Base Model Method(s):** `_ip_address`
*   **CLI Command(s):** `i` (info)

### `ip link show <interface> | grep ether | awk '{print $2}'`

*   **Description:** Shows the MAC address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface`
*   **Base Model Method(s):** `mac_address`
*   **CLI Command(s):** `i` (info)

### `ip route show default | awk '{print $5}'`

*   **Description:** Determines the default network interface used for internet traffic.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `default_interface`
*   **CLI Command(s):** `i` (info)

## `iw` - IW Command

`iw` is a tool to show and manipulate wireless devices and their configuration.

### `iw dev | grep Interface | cut -d' ' -f2`

*   **Description:** Lists all wireless network interfaces.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `detect_wifi_interface`
*   **CLI Command(s):** `i` (info)

### `iw dev <interface> info`

*   **Description:** Checks if a given network interface is a Wi-Fi interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `is_wifi_interface?`
*   **CLI Command(s):** (Internal validation)

## `xdg-open`

`xdg-open` is a desktop-independent tool for opening files and URLs from the command line.

### `xdg-open <application_name>`

*   **Description:** Opens a specified application.
*   **Dynamic Values:** `application_name`
*   **Base Model Method(s):** `open_application`
*   **CLI Command(s):** `ro` (open resource)

### `xdg-open <resource_url>`

*   **Description:** Opens a URL in the default web browser.
*   **Dynamic Values:** `resource_url`
*   **Base Model Method(s):** `open_resource`
*   **CLI Command(s):** `ro` (open resource)
