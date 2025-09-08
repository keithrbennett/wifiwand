# OS Command Usage for Ubuntu

### os-command-use-ubuntu-gemini.md

### 2025-09-09T21:21:00Z

This document details the shell commands used by `wifi-wand` on the Ubuntu operating system.

## Network Management with `nmcli`

On Ubuntu, `wifi-wand` relies heavily on `nmcli`, the command-line interface for NetworkManager. A key concept in NetworkManager is the distinction between a Wi-Fi network (identified by its SSID) and a "connection profile".

*   **Wi-Fi Network (SSID):** The broadcast name of a wireless network (e.g., "MyHomeWiFi").
*   **Connection Profile:** A saved set of configurations for a network. This includes the SSID, password, IP settings, DNS servers, etc. You can have multiple profiles for the same SSID, which can sometimes be a source of confusion. `wifi-wand` attempts to manage this by finding the most recently used profile for a given SSID when performing actions.

Most `wifi-wand` commands manipulate these connection profiles rather than interacting with the Wi-Fi device directly.

---

## `iw`

Used for basic wireless device inspection.

### `iw dev | grep Interface | cut -d' ' -f2`

*   **Description:** Detects the primary Wi-Fi interface name.
*   **Dynamic Values:** None.
*   **Base Model Method:** `detect_wifi_interface`
*   **CLI Commands:** All (during initialization).

### `iw dev <interface> info`

*   **Description:** Checks if a given network interface is a Wi-Fi interface.
*   **Dynamic Values:** `interface`
*   **Base Model Method:** `is_wifi_interface?`
*   **CLI Commands:** All (during initialization).

---

## `nmcli`

The primary tool for managing network connections on Ubuntu.

### `nmcli radio wifi`

*   **Description:** Checks if the Wi-Fi radio is enabled.
*   **Dynamic Values:** None.
*   **Base Model Method:** `wifi_on?`
*   **CLI Commands:** `w`, `i`, `a`, `s`, `cy`

### `nmcli radio wifi [on|off]`

*   **Description:** Turns the Wi-Fi radio on or off.
*   **Dynamic Values:** `on` or `off`.
*   **Base Model Methods:** `wifi_on`, `wifi_off`
*   **CLI Commands:** `on`, `of`, `cy`

### `nmcli -t -f SSID,SIGNAL dev wifi list`

*   **Description:** Lists available Wi-Fi networks with their signal strength.
*   **Dynamic Values:** None.
*   **Base Model Method:** `_available_network_names`
*   **CLI Commands:** `a`

### `nmcli -t -f active,ssid device wifi | ...`

*   **Description:** Gets the SSID of the currently connected Wi-Fi network.
*   **Dynamic Values:** None.
*   **Base Model Method:** `_connected_network_name`
*   **CLI Commands:** `ne`, `i`, `s`, `co`, `qr`

### `nmcli dev wifi connect <network_name> [password <password>]`

*   **Description:** Connects to a Wi-Fi network, creating a new connection profile.
*   **Dynamic Values:** `network_name`, `password`
*   **Base Model Method:** `_connect`
*   **CLI Commands:** `co`

### `nmcli connection up <profile>`

*   **Description:** Activates an existing connection profile.
*   **Dynamic Values:** `profile` (the name of the connection profile).
*   **Base Model Methods:** `_connect`, `set_nameservers`
*   **CLI Commands:** `co`, `na`

### `nmcli connection modify <profile> <security_param> <password>`

*   **Description:** Modifies the password of an existing connection profile.
*   **Dynamic Values:** `profile`, `security_param`, `password`
*   **Base Model Method:** `_connect`
*   **CLI Commands:** `co`

### `nmcli -t -f SSID,SECURITY dev wifi list`

*   **Description:** Gets the security type (e.g., WPA2) of available networks.
*   **Dynamic Values:** None.
*   **Base Model Methods:** `get_security_parameter`, `connection_security_type`
*   **CLI Commands:** `co`, `qr` (indirectly)

### `nmcli -t -f NAME,TIMESTAMP connection show`

*   **Description:** Lists saved connection profiles with their last-used timestamp.
*   **Dynamic Values:** None.
*   **Base Model Method:** `find_best_profile_for_ssid`
*   **CLI Commands:** `co` (indirectly)

### `nmcli connection delete <network_name>`

*   **Description:** Deletes a saved connection profile.
*   **Dynamic Values:** `network_name`
*   **Base Model Method:** `remove_preferred_network`
*   **CLI Commands:** `f`

### `nmcli -t -f NAME connection show`

*   **Description:** Lists the names of all saved connection profiles.
*   **Dynamic Values:** None.
*   **Base Model Method:** `preferred_networks`
*   **CLI Commands:** `pr`, `f`

### `nmcli --show-secrets connection show <name> | ...`

*   **Description:** Retrieves the stored password for a saved connection profile.
*   **Dynamic Values:** `preferred_network_name`
*   **Base Model Method:** `_preferred_network_password`
*   **CLI Commands:** `pa`, `qr` (indirectly)

### `nmcli dev disconnect <interface>`

*   **Description:** Disconnects the Wi-Fi interface from the current network.
*   **Dynamic Values:** `interface`
*   **Base Model Method:** `_disconnect`
*   **CLI Commands:** `d`

### `nmcli connection modify <connection> ipv4.dns "..."`

*   **Description:** Sets the DNS servers for a specific connection profile.
*   **Dynamic Values:** `current_connection`, DNS server IPs.
*   **Base Model Method:** `set_nameservers`
*   **CLI Commands:** `na`

### `nmcli connection modify <connection> ipv4.ignore-auto-dns [yes|no]`

*   **Description:** Configures whether to use DNS servers provided by the network.
*   **Dynamic Values:** `current_connection`
*   **Base Model Method:** `set_nameservers`
*   **CLI Commands:** `na`

### `nmcli connection show <connection_name>`

*   **Description:** Shows detailed information for a connection profile, used to get DNS servers.
*   **Dynamic Values:** `connection_name`
*   **Base Model Method:** `nameservers_from_connection`
*   **CLI Commands:** `na`

---

## `ip`

Used for inspecting network interface details.

### `ip -4 addr show <interface> | ...`

*   **Description:** Gets the IPv4 address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface`
*   **Base Model Method:** `_ip_address`
*   **CLI Commands:** `i`

### `ip link show <interface> | ...`

*   **Description:** Gets the MAC address of the Wi-Fi interface.
*   **Dynamic Values:** `wifi_interface`
*   **Base Model Method:** `mac_address`
*   **CLI Commands:** `i`

### `ip route show default | ...`

*   **Description:** Finds the network interface for the default route.
*   **Dynamic Values:** None.
*   **Base Model Method:** `default_interface`
*   **CLI Commands:** `i`

---

## `xdg-open`

### `xdg-open <resource_url>`

*   **Description:** Opens a URL or file with the default application.
*   **Dynamic Values:** `resource_url`
*   **Base Model Method:** `open_resource`
*   **CLI Commands:** `ro`

---

## `which`

### `which [command]`

*   **Description:** Checks if a command is available in the system's PATH.
*   **Dynamic Values:** `command` (`iw`, `nmcli`)
*   **Base Model Method:** `validate_os_preconditions`
*   **CLI Commands:** All (during initialization).