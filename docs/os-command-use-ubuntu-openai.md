# Ubuntu OS Command Use
### os-command-use-ubuntu
### 2025-09-08 00:00:00 UTC

Ubuntu WiFi management uses NetworkManager (`nmcli`) for connection profiles and radio control, `iw` for wireless interface discovery/validation, and `ip` for addressing and routing details. Key concept: NetworkManager maintains connection profiles (stored configurations) that are distinct from SSIDs; multiple profiles can exist for the same SSID (e.g., "MySSID", "MySSID 1"). This project prefers the most recently used profile by `TIMESTAMP` when duplicates exist.

## WiFi Interface Detection

**`iw dev | grep Interface | cut -d' ' -f2`**
- Finds the first WiFi interface name.
- Dynamic values: none
- Base model methods: `UbuntuModel#detect_wifi_interface`
- CLI commands: all WiFi operations (automatic interface detection during init)
- Notes: Uses piped `grep`/`cut` to extract interface names from `iw` output.

**`iw dev {interface} info 2>/dev/null`**
- Validates if an interface is WiFi-capable.
- Dynamic values: `{interface}` from `wifi_interface`
- Base model methods: `UbuntuModel#is_wifi_interface?`
- CLI commands: internal validation during init

## Radio Control

**`nmcli radio wifi`**
- Reports WiFi radio state (`enabled`/`disabled`).
- Dynamic values: none
- Base model methods: `UbuntuModel#wifi_on?`
- CLI commands: `w` (wifi status), used internally by several commands

**`nmcli radio wifi on`**
- Enables WiFi radio.
- Dynamic values: none
- Base model methods: `UbuntuModel#wifi_on`
- CLI commands: `on`

**`nmcli radio wifi off`**
- Disables WiFi radio.
- Dynamic values: none
- Base model methods: `UbuntuModel#wifi_off`
- CLI commands: `of`

## Network Discovery and Status

**`nmcli -t -f SSID,SIGNAL dev wifi list`**
- Lists available SSIDs with signal; parsed and sorted by signal strength.
- Dynamic values: none
- Base model methods: `UbuntuModel#_available_network_names`
- CLI commands: `a` (available networks)
- Notes: Output is `SSID:SIGNAL`; code sorts descending by signal and de-duplicates SSIDs.

**`nmcli -t -f active,ssid device wifi | egrep '^yes' | cut -d\: -f2`**
- Gets SSID of the currently connected network.
- Dynamic values: none
- Base model methods: `UbuntuModel#_connected_network_name`
- CLI commands: `ne` (network name), `i` (info), status rendering

## Connection and Profiles (NetworkManager)

NetworkManager profiles are named connections that may or may not equal the SSID. This code:
- Finds the best profile for an SSID using `nmcli -t -f NAME,TIMESTAMP connection show` and choosing the highest `TIMESTAMP`.
- Determines security to choose correct password parameter (`.psk` vs `.wep-key0`) using scan results.

**`nmcli -t -f NAME,TIMESTAMP connection show`**
- Lists profiles with last-used timestamps; used to pick the most recent profile for an SSID.
- Dynamic values: none
- Base model methods: `UbuntuModel#find_best_profile_for_ssid` (private)
- CLI commands: `co` (connect)

**`nmcli -t -f SSID,SECURITY dev wifi list`**
- Reads security type (e.g., WPA2/WPA3/WEP) for a given SSID to select parameter.
- Dynamic values: `{ssid}` (matched within output)
- Base model methods: `UbuntuModel#get_security_parameter`/`#security_parameter` (private), `UbuntuModel#connection_security_type`
- CLI commands: `co` (connect), `qr` (QR metadata), `i` (info)
- Notes: Maps security to `802-11-wireless-security.psk` for WPA/WPA2/WPA3, `...wep-key0` for WEP; enterprise/EAP treated as unsupported for PSK.

**`nmcli dev wifi connect {ssid}`**
- Connects to an open network or creates a new profile.
- Dynamic values: `{ssid}`
- Base model methods: `UbuntuModel#_connect`
- CLI commands: `co`

**`nmcli dev wifi connect {ssid} password {password}`**
- Connects with password, creating a profile if needed.
- Dynamic values: `{ssid}`, `{password}`
- Base model methods: `UbuntuModel#_connect`
- CLI commands: `co`

**`nmcli connection up {profile_name}`**
- Activates an existing connection profile.
- Dynamic values: `{profile_name}` (often starts with the SSID)
- Base model methods: `UbuntuModel#_connect`, `UbuntuModel#set_nameservers`
- CLI commands: `co`, `na`

**`nmcli connection modify {profile_name} 802-11-wireless-security.psk {password}`**
- Updates stored WPA/WPA2/WPA3 password on an existing profile.
- Dynamic values: `{profile_name}`, `{password}`
- Base model methods: `UbuntuModel#_connect`
- CLI commands: `co`

**`nmcli connection modify {profile_name} 802-11-wireless-security.wep-key0 {password}`**
- Updates stored WEP key when security is WEP.
- Dynamic values: `{profile_name}`, `{password}`
- Base model methods: `UbuntuModel#_connect`
- CLI commands: `co`

**`nmcli -t -f NAME connection show`**
- Lists saved profiles (preferred networks).
- Dynamic values: none
- Base model methods: `UbuntuModel#preferred_networks`
- CLI commands: `pr`

**`nmcli connection delete {profile_name}`**
- Deletes a stored profile.
- Dynamic values: `{profile_name}`
- Base model methods: `UbuntuModel#remove_preferred_network`
- CLI commands: `f`

**`nmcli dev disconnect {interface}`**
- Disconnects the WiFi interface from any network.
- Dynamic values: `{interface}` from `wifi_interface`
- Base model methods: `UbuntuModel#_disconnect`
- CLI commands: `d`
- Notes: Exit code 6 (device not active) is handled as a non-error.

**`nmcli --show-secrets connection show {profile_name} | grep '802-11-wireless-security.psk:' | cut -d':' -f2-`**
- Retrieves stored PSK password for a profile.
- Dynamic values: `{profile_name}`
- Base model methods: `UbuntuModel#_preferred_network_password`
- CLI commands: `pa`

## DNS (Nameservers)

Ubuntu/NetworkManager stores DNS per connection profile; avoid editing `/etc/resolv.conf` directly.

**`nmcli connection show {profile_name}`**
- Reads DNS for the active profile (looks for `ipv4.dns[1]:` entries).
- Dynamic values: `{profile_name}` (current active connection)
- Base model methods: `UbuntuModel#nameservers_from_connection`
- CLI commands: `na get`

**`nmcli connection modify {profile_name} ipv4.dns "{dns_list}"`**
- Sets custom DNS servers on the active profile; also sets `ipv4.ignore-auto-dns yes`.
- Dynamic values: `{profile_name}`, `{dns_list}` (space-separated IPv4 addresses)
- Base model methods: `UbuntuModel#set_nameservers`
- CLI commands: `na` (set)

**`nmcli connection modify {profile_name} ipv4.dns ""`**
- Clears custom DNS; also sets `ipv4.ignore-auto-dns no`.
- Dynamic values: `{profile_name}`
- Base model methods: `UbuntuModel#set_nameservers`
- CLI commands: `na clear`

**`nmcli connection up {profile_name}`**
- Restarts connection to apply DNS changes.
- Dynamic values: `{profile_name}`
- Base model methods: `UbuntuModel#set_nameservers`
- CLI commands: `na`

**`/etc/resolv.conf` (file read)**
- Fallback read of nameservers when profile data not available.
- Dynamic values: none
- Base model methods: `UbuntuModel#nameservers_using_resolv_conf`, `BaseModel#nameservers_using_resolv_conf`
- CLI commands: `na get` (indirect)

## Addressing, Routes, System Open

**`ip -4 addr show {interface} | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1`**
- Gets IPv4 address for WiFi interface.
- Dynamic values: `{interface}` from `wifi_interface`
- Base model methods: `UbuntuModel#_ip_address`
- CLI commands: `i`

**`ip link show {interface} | grep ether | awk '{print $2}'`**
- Gets MAC address for WiFi interface.
- Dynamic values: `{interface}` from `wifi_interface`
- Base model methods: `UbuntuModel#mac_address`
- CLI commands: `i`

**`ip route show default | awk '{print $5}'`**
- Gets default route interface.
- Dynamic values: none
- Base model methods: `UbuntuModel#default_interface`
- CLI commands: `i` (indirect)

**`xdg-open {resource_url}`**
- Opens a URL or file using the desktop default handler.
- Dynamic values: `{resource_url}`
- Base model methods: `UbuntuModel#open_resource`
- CLI commands: `ro`

## QR Code Generation

Requires `qrencode` to be installed (`sudo apt install qrencode`).

**`qrencode -o {file} {wifi_qr_string}`**
- Writes a QR image file (PNG by default, `-t SVG`/`-t EPS` for other types).
- Dynamic values: `{file}` (default: `{SSID}-qr-code.png`), `{wifi_qr_string}` (generated from SSID/security/password)
- Base model methods: `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_file!`
- CLI commands: `qr [filespec]`

**`qrencode -t ANSI {wifi_qr_string}`**
- Prints an ANSI QR code to stdout when filespec is `-`.
- Dynamic values: `{wifi_qr_string}`
- Base model methods: `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_text!`
- CLI commands: `qr -`

**`which qrencode`**
- Checked to ensure `qrencode` is available; suggests install if missing.
- Dynamic values: none
- Base model methods: `Helpers::QrCodeGenerator#ensure_qrencode_available!`
- CLI commands: `qr` (pre-check)

## Public IP Info (Info Command)

**`curl -s ipinfo.io`**
- Fetches public IP metadata; used only if internet connectivity appears up.
- Dynamic values: none
- Base model methods: `BaseModel#public_ip_address_info` (used by `#wifi_info`)
- CLI commands: `i` (info)

## OS Detection (Ubuntu)

These checks determine whether the current OS matches Ubuntu:

**`cat /etc/os-release` (file read)** and search for `ID=ubuntu`
- Base OS methods: `Ubuntu#current_os_is_this_os?`

**`lsb_release -i | grep -q "Ubuntu"`**
- Base OS methods: `Ubuntu#current_os_is_this_os?`

**`cat /proc/version` (file read)** and search for `Ubuntu`
- Base OS methods: `Ubuntu#current_os_is_this_os?`

## Notes on Profiles vs SSIDs (Ubuntu)

- Profiles (connections) are stored configurations managed by NetworkManager and may not equal the SSID; duplicates (e.g., "SSID", "SSID 1") are common.
- This code selects the most recently used profile by `TIMESTAMP` when multiple names start with the target SSID.
- Password updates choose parameter based on security: WPA/WPA2/WPA3 -> `.psk`, WEP -> `.wep-key0`. Enterprise (802.1x/EAP) is intentionally unsupported for PSK-based flows.

