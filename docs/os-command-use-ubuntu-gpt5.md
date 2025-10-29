# Ubuntu OS Command Use
### os-command-use-ubuntu-gpt5.md
### 2025-10-29 14:33:58 UTC

This document outlines the shell commands used by `wifi-wand` on the Ubuntu operating system.

Notes:
- Ubuntu support relies on NetworkManager; `nmcli connection ...` operates on saved profiles that may differ from visible SSIDs (e.g., `"MySSID 1"`).
- All invocations run through `BaseModel#run_os_command`, which centralizes logging, timeouts, and non-raising retries when requested.

## `iw`

`iw` provides low-level wireless interface details that seed later NetworkManager calls.

### `iw dev`
- Description: Lists Wi-Fi interfaces so the model can pick the active wireless device.
- Dynamic Values: None
- Base Model Method(s): `detect_wifi_interface`
- CLI Command(s): Internal (model initialization for all Wi-Fi-aware commands)
- Helpful Info: Parses the first `Interface <name>` line and caches the result (e.g., `wlp0s20f3`).

### `iw dev <interface> info 2>/dev/null`
- Description: Verifies whether a provided interface exposes Wi-Fi capabilities.
- Dynamic Values: `interface`
- Base Model Method(s): `is_wifi_interface?`
- CLI Command(s): Internal (validates `--wifi-interface` overrides before executing other commands)
- Helpful Info: Uses the shell form to silence stderr when probing nonexistent or down interfaces.

## `nmcli`

`nmcli` drives NetworkManager for radio state, connection management, DNS, and credential handling.

### `nmcli radio wifi`
- Description: Reports whether the Wi-Fi radio is enabled.
- Dynamic Values: None
- Base Model Method(s): `wifi_on?`
- CLI Command(s): `a`, `ci`, `cy`, `d`, `i`, `na`, `ne`, `of`, `on`, `s`, `w`
- Helpful Info: Interprets `enabled`/`disabled` text; failures are non-fatal (queried with `raise_on_error: false`).

### `nmcli radio wifi on`
- Description: Turns on the Wi-Fi radio before connection attempts.
- Dynamic Values: None
- Base Model Method(s): `wifi_on`
- CLI Command(s): `co`, `cy`, `on`
- Helpful Info: Skips the call if Wi-Fi is already on, then waits for confirmation with the status waiter.

### `nmcli radio wifi off`
- Description: Powers down the Wi-Fi radio.
- Dynamic Values: None
- Base Model Method(s): `wifi_off`
- CLI Command(s): `cy`, `of`
- Helpful Info: Retries radio state until confirmed off; raises `WifiDisableError` if the radio stays on.

### `nmcli -t -f SSID,SIGNAL dev wifi list`
- Description: Scans for nearby networks with signal strength metadata.
- Dynamic Values: None
- Base Model Method(s): `_available_network_names`
- CLI Command(s): `a`
- Helpful Info: Produces colon-delimited `SSID:SIGNAL` lines that are sorted by descending signal and deduplicated.

### `nmcli -t -f active,ssid device wifi`
- Description: Retrieves the active Wi-Fi connection and SSID.
- Dynamic Values: None
- Base Model Method(s): `_connected_network_name`
- CLI Command(s): `ci`, `co`, `i`, `na`, `ne`, `s`
- Helpful Info: Looks for the first line beginning with `yes:`; executed with `raise_on_error: false` to allow offline polling.

### `nmcli connection modify <profile> <security_param> <password>`
- Description: Updates a saved connection profile with a new PSK/WEP credential.
- Dynamic Values: `profile`, `security_param`, `password`
- Base Model Method(s): `_connect`
- CLI Command(s): `co`
- Helpful Info: `security_param` is derived from a fresh scan (`802-11-wireless-security.psk`, `.wep-key0`, etc.) to match the network’s security suite.

### `nmcli dev wifi connect <network_name> password <password>`
- Description: Creates or activates a connection using the provided SSID and password.
- Dynamic Values: `network_name`, `password`
- Base Model Method(s): `_connect`
- CLI Command(s): `co`
- Helpful Info: Serves as a fallback when no profile exists or its security type could not be resolved.

### `nmcli connection up <profile>`
- Description: Brings an existing connection profile online.
- Dynamic Values: `profile`
- Base Model Method(s): `_connect`, `set_nameservers`
- CLI Command(s): `co`, `na`
- Helpful Info: Used both after credential updates and after DNS edits to apply profile changes without recreating the connection.

### `nmcli dev wifi connect <network_name>`
- Description: Attempts to join an open network when no password is supplied.
- Dynamic Values: `network_name`
- Base Model Method(s): `_connect`
- CLI Command(s): `co`
- Helpful Info: Assumes the target network is unsecured or already has stored credentials within NetworkManager.

### `nmcli -t -f SSID,SECURITY dev wifi list`
- Description: Scans for networks and their advertised security suites.
- Dynamic Values: None
- Base Model Method(s): `get_security_parameter`, `connection_security_type`
- CLI Command(s): `co`, `qr`
- Helpful Info: Runs with `raise_on_error: false` to tolerate transient scan failures; results like `WPA2 WPA3` are normalized to canonical values.

### `nmcli -t -f NAME,TIMESTAMP connection show`
- Description: Lists saved connection profiles with their last-used timestamps.
- Dynamic Values: None
- Base Model Method(s): `find_best_profile_for_ssid`
- CLI Command(s): `co`
- Helpful Info: Helps disambiguate duplicate profiles (`SSID`, `SSID 1`, etc.) by picking the most recently used entry.

### `nmcli connection delete <network_name>`
- Description: Removes a stored NetworkManager profile.
- Dynamic Values: `network_name`
- Base Model Method(s): `remove_preferred_network`
- CLI Command(s): `f`
- Helpful Info: Only runs when the profile is known to exist to avoid noisy “Unknown connection” errors.

### `nmcli -t -f NAME connection show`
- Description: Returns all saved connection profile names.
- Dynamic Values: None
- Base Model Method(s): `preferred_networks`
- CLI Command(s): `co`, `pr`
- Helpful Info: Output is sorted before returning so CLI listings remain stable across runs.

### `nmcli --show-secrets connection show <preferred_network_name>`
- Description: Reads the stored pre-shared key for a saved network.
- Dynamic Values: `preferred_network_name`
- Base Model Method(s): `_preferred_network_password`
- CLI Command(s): `co`, `pa`
- Helpful Info: Searches for `802-11-wireless-security.psk:` lines and strips blank passwords; invoked with `raise_on_error: false` to handle locked secrets.

### `nmcli dev disconnect <interface>`
- Description: Requests a disconnect from the given Wi-Fi interface.
- Dynamic Values: `interface`
- Base Model Method(s): `_disconnect`
- CLI Command(s): `d`
- Helpful Info: Suppresses `nmcli` exit status 6 (already disconnected) so repeated disconnects do not raise.

### `nmcli connection modify <current_connection> ipv4.dns ''`
- Description: Clears custom IPv4 DNS servers for the active profile.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Paired with `ipv4.ignore-auto-dns no` to hand DNS control back to DHCP; executed with `raise_on_error: false`.

### `nmcli connection modify <current_connection> ipv4.ignore-auto-dns no`
- Description: Re-enables automatic IPv4 DNS acquisition.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Restores DHCP-provided DNS after clearing custom entries; tolerant of missing properties.

### `nmcli connection modify <current_connection> ipv6.dns ''`
- Description: Clears custom IPv6 DNS servers for the active profile.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Mirrors the IPv4 clear path so dual-stack networks return to automatic DNS.

### `nmcli connection modify <current_connection> ipv6.ignore-auto-dns no`
- Description: Re-enables automatic IPv6 DNS acquisition.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Ensures DHCPv6 or RA-provided DNS resumes once manual settings are cleared.

### `nmcli connection modify <current_connection> ipv4.dns <ipv4_dns_string>`
- Description: Applies custom IPv4 DNS servers to the active profile.
- Dynamic Values: `current_connection`, `ipv4_dns_string`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Accepts space-separated IPv4 addresses and pairs with `ipv4.ignore-auto-dns yes` to prevent DHCP overrides.

### `nmcli connection modify <current_connection> ipv4.ignore-auto-dns yes`
- Description: Instructs NetworkManager to prefer the configured IPv4 DNS servers.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Without this flag, NetworkManager would append DHCP DNS servers alongside the custom list.

### `nmcli connection modify <current_connection> ipv6.dns <ipv6_dns_string>`
- Description: Applies custom IPv6 DNS servers to the active profile.
- Dynamic Values: `current_connection`, `ipv6_dns_string`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Supports space-separated IPv6 literals and works in tandem with `ipv6.ignore-auto-dns yes`.

### `nmcli connection modify <current_connection> ipv6.ignore-auto-dns yes`
- Description: Forces NetworkManager to honor custom IPv6 DNS servers.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Prevents router advertisements from reintroducing automatic IPv6 resolvers.

### `nmcli connection up <current_connection>`
- Description: Reapplies the active connection so DNS edits take effect immediately.
- Dynamic Values: `current_connection`
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na`
- Helpful Info: Runs with `raise_on_error: false` because the connection may already be active yet still needs a reload.

### `nmcli -t -f GENERAL.CONNECTION dev show <interface>`
- Description: Resolves the Connection profile bound to a specific device.
- Dynamic Values: `interface`
- Base Model Method(s): `active_connection_profile_name`
- CLI Command(s): `i`, `na`, `qr`
- Helpful Info: Pulls `GENERAL.CONNECTION:<name>` and ignores blank entries to avoid treating wired profiles as Wi-Fi.

### `nmcli connection show <connection_name>`
- Description: Dumps full connection settings, including runtime DNS fields.
- Dynamic Values: `connection_name`
- Base Model Method(s): `nameservers_from_connection`
- CLI Command(s): `i`, `na`
- Helpful Info: Filters lines matching `/ipv4\.dns/` and `/IP4.DNS/` (and IPv6 variants) to merge static and runtime resolvers.

### `nmcli -t -f 802-11-wireless.hidden connection show <profile_name>`
- Description: Determines whether the active network is marked as hidden.
- Dynamic Values: `profile_name`
- Base Model Method(s): `network_hidden?`
- CLI Command(s): `qr`
- Helpful Info: Feeds the QR generator so hidden SSIDs emit `H:true`; executed with `raise_on_error: false`.

## `ip`

`ip` provides interface addressing and routing data that supplements NetworkManager state.

### `ip -4 addr show <wifi_interface>`
- Description: Fetches IPv4 address assignments for the Wi-Fi interface.
- Dynamic Values: `wifi_interface`
- Base Model Method(s): `_ip_address`
- CLI Command(s): `i`, `s`
- Helpful Info: Extracts the first `inet` token (`x.y.z.w/nn`) and strips the prefix length to return the host address.

### `ip link show <wifi_interface>`
- Description: Retrieves link-layer details, including the MAC address.
- Dynamic Values: `wifi_interface`
- Base Model Method(s): `mac_address`
- CLI Command(s): `i`, `s`
- Helpful Info: Reads the token after `link/ether`; gracefully returns `nil` if the interface is down or unnamed.

### `ip route show default`
- Description: Identifies the interface handling the system’s default route.
- Dynamic Values: None
- Base Model Method(s): `default_interface`
- CLI Command(s): `i`, `s`
- Helpful Info: Parses the first route line and returns the value following the `dev` field.

## `xdg-open`

### `xdg-open <resource_url>`
- Description: Opens a URL or file with the desktop’s default handler.
- Dynamic Values: `resource_url`
- Base Model Method(s): `open_resource`
- CLI Command(s): `ro`
- Helpful Info: Delegates to the desktop environment; failures raise if the handler is missing or the URL is malformed.
