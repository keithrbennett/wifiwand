# Ubuntu OS Command Usage

### os-command-use-ubuntu-zai.md

### 2025-08-26 13:34:23 UTC

This document outlines the shell commands used by `wifi-wand` on the Ubuntu operating system.

## Network Manager Information

Ubuntu uses NetworkManager which maintains network profiles that can contain saved passwords and connection settings. These profiles are distinct from SSIDs - a network SSID may have multiple profiles with different configurations.

## `nmcli` - NetworkManager Command Line Interface

`nmcli` is the primary tool used for managing network connections on Ubuntu. It interacts with NetworkManager to control Wi-Fi adapters, scan for networks, and manage connection profiles.

### `nmcli radio wifi`

*   **Description:** Checks if the Wi-Fi radio is enabled.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_on?`
*   **CLI Command(s):** `w` (wifi_on)

### `nmcli radio wifi on`

*   **Description:** Turns the Wi-Fi radio on.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_on`
*   **CLI Command(s):** `on`

### `nmcli radio wifi off`

*   **Description:** Turns the Wi-Fi radio off.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `wifi_off`
*   **CLI Command(s):** `of` (off)

### `nmcli -t -f SSID,SIGNAL dev wifi list`

*   **Description:** Lists available Wi-Fi networks with their signal strength, sorted by signal strength descending.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_available_network_names`
*   **CLI Command(s):** `a` (avail_nets)

### `nmcli -t -f active,ssid device wifi`

*   **Description:** Shows the SSID of the currently active Wi-Fi connection.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `_connected_network_name`
*   **CLI Command(s):** `ne` (network_name)

### `nmcli dev wifi list | grep <ssid>`

*   **Description:** Retrieves the full details of a specific network from the scan list to determine its security type (WPA2, WEP, etc.).
*   **Dynamic Values:** `ssid` (network name to search for)
*   **Base Model Method(s):** `get_security_type`
*   **CLI Command(s):** `co` (connect)

### `nmcli connection up <network_name>`

*   **Description:** Activates an existing NetworkManager connection profile for the specified network.
*   **Dynamic Values:** `network_name` (name of the NetworkManager connection profile)
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli -t -f NAME connection show`

*   **Description:** Lists the names of all saved NetworkManager connection profiles (preferred networks).
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `preferred_networks`
*   **CLI Command(s):** `pr` (pref_nets)

### `nmcli connection modify <network_name> 802-11-wireless-security.psk <password>`

*   **Description:** Updates the password for an existing NetworkManager connection profile, preserving other security settings.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli dev wifi connect <network_name> password <password>`

*   **Description:** Connects to a Wi-Fi network, creating a new NetworkManager profile if one doesn't exist.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method(s):** `_connect`
*   **CLI Command(s):** `co` (connect)

### `nmcli connection delete <network_name>`

*   **Description:** Deletes a NetworkManager connection profile, removing saved passwords and settings.
*   **Dynamic Values:** `network_name`
*   **Base Model Method(s):** `remove_preferred_network`
*   **CLI Command(s):** `f` (forget)

### `nmcli --show-secrets connection show <network_name> | grep '802-11-wireless-security.psk:' | cut -d':' -f2-`

*   **Description:** Retrieves the saved password for a NetworkManager connection profile.
*   **Dynamic Values:** `preferred_network_name` (name of the NetworkManager connection profile)
*   **Base Model Method(s):** `_preferred_network_password`
*   **CLI Command(s):** `pa` (password)

### `nmcli dev disconnect <interface>`

*   **Description:** Disconnects a specific network interface from any active connection.
*   **Dynamic Values:** `interface` (network interface name)
*   **Base Model Method(s):** `_disconnect`
*   **CLI Command(s):** `d` (disconnect)

### `nmcli connection modify <interface> ipv4.dns "<dns_servers>"`

*   **Description:** Sets the DNS servers for a network connection by modifying the NetworkManager connection profile.
*   **Dynamic Values:** `interface`, `dns_servers` (space-separated list of IP addresses)
*   **Base Model Method(s):** `set_nameservers`
*   **CLI Command(s):** `na` (nameservers)

### `nmcli connection modify <interface> ipv4.dns ""`

*   **Description:** Clears custom DNS servers from a NetworkManager connection profile.
*   **Dynamic Values:** `interface`
*   **Base Model Method(s):** `set_nameservers`
*   **CLI Command(s):** `na clear` (nameservers clear)

## `ip` - IP Command

The `ip` command is used to show and manipulate routing, devices, policy routing and tunnels.

### `ip -4 addr show <interface> | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1`

*   **Description:** Shows the IPv4 address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface` (network interface name)
*   **Base Model Method(s):** `_ip_address`
*   **CLI Command(s):** `i` (info)

### `ip link show <interface> | grep ether | awk '{print $2}'`

*   **Description:** Shows the MAC address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface` (network interface name)
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

*   **Description:** Lists all wireless network interfaces and returns the first one found.
*   **Dynamic Values:** None.
*   **Base Model Method(s):** `detect_wifi_interface`
*   **CLI Command(s):** `i` (info), `w` (wifi_on), `ne` (network_name)

### `iw dev <interface> info`

*   **Description:** Checks if a given network interface is a Wi-Fi interface by checking if device info can be retrieved.
*   **Dynamic Values:** `interface` (network interface name to test)
*   **Base Model Method(s):** `is_wifi_interface?`
*   **CLI Command(s):** (Internal validation used by various commands)

## `xdg-open`

`xdg-open` is a desktop-independent tool for opening files and URLs from the command line.

### `xdg-open <application_name>`

*   **Description:** Opens a specified application using the system's default handler.
*   **Dynamic Values:** `application_name`
*   **Base Model Method(s):** `open_application`
*   **CLI Command(s):** `ro` (ropen) with resource codes

### `xdg-open <resource_url>`

*   **Description:** Opens a URL in the default web browser.
*   **Dynamic Values:** `resource_url`
*   **Base Model Method(s):** `open_resource`
*   **CLI Command(s):** `ro` (ropen) with resource codes