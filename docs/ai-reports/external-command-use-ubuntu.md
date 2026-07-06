# OS Command Use for Ubuntu
### 2026-07-06-12-46-os-command-use-ubuntu-claude-sonnet-5.md
### 2026-07-06 12:46 UTC

## Overview

The Ubuntu model lives in `lib/wifi_wand/platforms/ubuntu/model.rb`. Wi-Fi commands are issued through
`BaseModel#run_command`, which delegates to `CommandExecutor#run_command_using_args`. That path only
accepts `Array` arguments (e.g. `['nmcli', 'radio', 'wifi', 'on']`) and refuses shell-interpreted strings,
so none of the commands below are vulnerable to shell injection from dynamic values. Timeouts, stdout
logging, and error-raising behavior are configured per call via keyword arguments such as
`raise_on_error: false` and `timeout_in_secs:`.

Startup precondition checks use `CommandExecutor#command_available?`, which searches `PATH` directly
instead of spawning a command. The three core Wi-Fi utilities validated at startup are:

- `iw` (package: `iw`)
- `nmcli` (package: `network-manager`)
- `ip` (package: `iproute2`)

Two optional dependencies are checked lazily, only on the code path that needs them, rather than at
startup:

- `xdg-open` (package: `xdg-utils`) — used only by `ropen`.
- `qrencode` (package: `qrencode`) — checked by `QrCodeGenerator` immediately before rendering a QR code.

Two Ruby helper scripts are also spawned directly via `Process.spawn` (not through `run_command`) for
connectivity and captive-portal probing. They are OS-agnostic (shared with other platforms), so they're
listed separately at the end rather than mixed in with the Ubuntu-specific Wi-Fi utilities.

## NetworkManager profiles vs. SSIDs

NetworkManager stores every known Wi-Fi network as a *connection profile*. A profile's name is often
identical to its SSID, but doesn't have to be — duplicate SSIDs can produce profiles named `MySSID`,
`MySSID 1`, etc. Because of this, `nmcli dev wifi ...` commands generally operate on SSIDs, while
`nmcli connection ...` commands generally operate on profile names, and WifiWand must resolve a
caller-supplied SSID to the "best" matching profile — the one with the most recent `TIMESTAMP` — before
running most `nmcli connection` commands.

---

## `iw dev`

**Description:** List wireless devices and discover the default managed Wi-Fi interface.

**Dynamic values:** none

**Base model methods:** `probe_wifi_interface`

**CLI commands:** any command that lazily initializes `wifi_interface` without `--wifi-interface` —
effectively all of them (`avail_nets`, `connect`, `cycle`, `disconnect`, `forget`, `info`, `nameservers`,
`network_name`, `off`, `on`, `password`, `pref_nets`, `qr`, `status`, `till`, `wifi_on`).

**Details:** Output is scanned for `Interface <name>` followed by `type managed`.

---

## `iw dev <interface> info`

**Description:** Validate that a caller-specified interface is actually a wireless interface.

**Dynamic values:** `<interface>` — the value supplied via `--wifi-interface`.

**Base model methods:** `is_wifi_interface?`

**CLI commands:** any command invoked with `--wifi-interface`.

**Details:** Runs with `raise_on_error: false`; a successful exit status is the validation result.

---

## `iw dev <interface> link`

**Description:** Read the SSID and BSSID currently associated with the interface.

**Dynamic values:** `<interface>` — `wifi_interface`.

**Base model methods:** `_connected_network_name`, `bssid`, `status_connected_network_name` (private),
plus transitively `network_hidden?` and `connection_security_type`, which both need the current SSID first.

**CLI commands:** `network_name`, `info`, `status`, `connect`, `disconnect`, `qr`,
`till associated` / `till disassociated`.

**Details:** A first line of `Not connected` means no active association. SSID is parsed from the
`SSID:` line; BSSID from `Connected to <bssid>`.

---

## `nmcli radio wifi`

**Description:** Check whether the Wi-Fi radio is enabled.

**Dynamic values:** none

**Base model methods:** `nmcli_wifi_radio_enabled?` (private), `wifi_on?`, `status_wifi_on?`; also used
by `wifi_on`/`wifi_off` as a post-condition poll.

**CLI commands:** `wifi_on`, `info`, `status`, `on`, `off`, `cycle`, `connect`, `disconnect`, `avail_nets`,
`till wifi_on` / `till wifi_off`.

**Details:** Stdout containing `enabled` is treated as on, after confirming a successful exit status.

---

## `nmcli radio wifi on`

**Description:** Turn the Wi-Fi radio on.

**Dynamic values:** none

**Base model methods:** `wifi_on` (also reached through `cycle_network` and `connect`).

**CLI commands:** `on`, `cycle`, `connect`.

**Details:** After running, the model polls `wifi_on?` until the radio reports enabled or a short
timeout expires.

---

## `nmcli radio wifi off`

**Description:** Turn the Wi-Fi radio off.

**Dynamic values:** none

**Base model methods:** `wifi_off` (also reached through `cycle_network`).

**CLI commands:** `off`, `cycle`.

**Details:** The model polls `wifi_on?` until the radio reports disabled.

---

## `nmcli -t -f SSID,SIGNAL dev wifi list`

**Description:** Scan for visible networks and return SSID plus signal strength.

**Dynamic values:** none

**Base model methods:** `_available_network_names`, `available_network_names`, `available_network_scan`.

**CLI commands:** `avail_nets`.

**Details:** Uses terse (`-t`) output parsed with `nmcli_split`, which understands nmcli's escaped colons
and backslashes in SSIDs. Results are sorted by signal descending; blank SSIDs are dropped and duplicates
removed.

---

## `nmcli -t -f SSID,SECURITY dev wifi list`

**Description:** Determine the security type advertised by a visible SSID.

**Dynamic values:** none in the command array — the target SSID is matched against parsed output.

**Base model methods:** `get_security_parameter`, `security_parameter`, `security_parameter_for_existing_profile`
(all private).

**CLI commands:** `connect`, when a password is being applied.

**Details:** Normalizes the advertised security so WifiWand knows whether to store the password in
`802-11-wireless-security.psk` (WPA/WPA2/WPA3) or `802-11-wireless-security.wep-key0` (WEP).

---

## `nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no`

**Description:** Read the signal strength of the currently associated BSS without triggering a fresh scan.

**Dynamic values:** none

**Base model methods:** `signal_quality_from_nmcli_scan` (private), `signal_quality`,
`status_signal_quality` (private).

**CLI commands:** `info`, `status`.

**Details:** The row with `IN-USE` equal to `*` is selected; its value is treated as a 0–100 percentage.

---

## `nmcli -t -f IN-USE,SSID,SECURITY dev wifi list`

**Description:** Read the security type of the currently connected BSS.

**Dynamic values:** none in the command array — the connected SSID comes from `_connected_network_name`.

**Base model methods:** `connection_security_type`.

**CLI commands:** `info`, `qr`.

**Details:** Matches the active row (`IN-USE == *`) against the connected SSID, then normalizes security
to `WPA3`, `WPA2`, `WPA`, `WEP`, or `NONE`. Empty and `--` fields mean an open network.

---

## `nmcli -t -f DEVICE connection show --active`

**Description:** Determine whether the Wi-Fi interface has an active NetworkManager connection.

**Dynamic values:** none in the command array — parsed output is compared against `wifi_interface`.

**Base model methods:** `connected?`, `disconnect_associated?`, `status_connected?` (private).

**CLI commands:** `info`, `status`, `connect`, `disconnect`, `network_name`, `nameservers`, `qr`,
`till associated` / `till disassociated`.

**Details:** Output rows are active device names; WifiWand checks for an exact match on the Wi-Fi
interface name.

---

## `nmcli dev wifi connect <network> [password <password>]`

**Description:** Connect to an SSID, optionally supplying a password.

**Dynamic values:** `<network>` — caller-supplied SSID. `<password>` — caller-supplied or saved password
when present.

**Base model methods:** `_connect`.

**CLI commands:** `connect`.

**Details:** Used when no saved profile exists for the SSID. Without a password the network is assumed
open. nmcli's stderr/exit status is pattern-matched into domain-specific exceptions:
`WifiWand::NetworkNotFoundError`, `NetworkAuthenticationError`, and `NetworkConnectionError`.

---

## `nmcli connection up <profile>`

**Description:** Activate an existing NetworkManager connection profile.

**Dynamic values:** `<profile>` — resolved profile name, usually the most recently used saved profile
for the SSID.

**Base model methods:** `_connect`, `activate_existing_profile_with_password` (private),
`set_nameservers`, `restore_dns_configuration`.

**CLI commands:** `connect`, `nameservers`.

**Details:** The normal reconnect path for a saved network. DNS edits are also applied by bringing the
modified profile up again.

---

## `nmcli connection modify <profile> <security-field> <password>`

**Description:** Update, or roll back, the stored password on a saved Wi-Fi profile.

**Dynamic values:** `<profile>` — resolved profile name. `<security-field>` —
`802-11-wireless-security.psk` or `802-11-wireless-security.wep-key0`. `<password>` — caller-supplied
password, or the prior password during rollback.

**Base model methods:** `activate_existing_profile_with_password` (private),
`rollback_existing_profile_password` (private).

**CLI commands:** `connect`.

**Details:** The profile is only modified when the new password differs from the stored one. If
activation then fails, WifiWand rolls back to the previous password.

---

## `nmcli connection delete <profile>`

**Description:** Delete a saved NetworkManager connection profile.

**Dynamic values:** `<profile>` — each profile whose stored SSID matches the caller's network name.

**Base model methods:** `remove_preferred_network`, `remove_preferred_networks` (transitively).

**CLI commands:** `forget`.

**Details:** Because one SSID can map to multiple profiles (e.g. `MySSID`, `MySSID 1`), WifiWand deletes
every profile whose stored SSID matches.

---

## `nmcli --show-secrets connection show <profile>`

**Description:** Read a saved profile's details, including its password secret field.

**Dynamic values:** `<profile>` — saved profile name.

**Base model methods:** `_preferred_network_password`, `preferred_network_secret_parameter` (private),
`preferred_network_password`.

**CLI commands:** `password`, `connect`, `qr`.

**Details:** Looks for `802-11-wireless-security.psk` and `802-11-wireless-security.wep-key0`; empty
values and `--` placeholders are ignored.

---

## `nmcli -t -f NAME,TYPE,TIMESTAMP connection show`

**Description:** Enumerate all saved NetworkManager connection profiles.

**Dynamic values:** none

**Base model methods:** `saved_wifi_profiles_from_summary_query` (private), `preferred_networks`,
`has_preferred_network?`, `preferred_networks_matching_ssid`, `find_best_profile_for_ssid` (private).

**CLI commands:** `pref_nets`, `forget`, `password`, `connect`, `qr`.

**Details:** Only rows with `TYPE == 802-11-wireless` are kept. SSIDs are resolved per-profile (see next
entry) using up to `SAVED_WIFI_PROFILE_SSID_LOOKUP_WORKERS` (8) concurrent worker threads.

---

## `nmcli -t -f 802-11-wireless.ssid connection show <profile>`

**Description:** Resolve the SSID stored inside a saved connection profile.

**Dynamic values:** `<profile>` — profile name from the profile-summary query.

**Base model methods:** `saved_wifi_profile_ssid` (private).

**CLI commands:** indirectly via `pref_nets`, `forget`, `password`, `connect`, `qr`.

**Details:** Exists because a NetworkManager profile name can't be assumed to equal its SSID; run in
parallel across up to 8 worker threads while building the saved-profile cache.

---

## `nmcli -t -f GENERAL.CONNECTION dev show <interface>`

**Description:** Find the active NetworkManager profile name for a Wi-Fi interface.

**Dynamic values:** `<interface>` — `wifi_interface`.

**Base model methods:** `active_connection_profile_name`; transitively used by `nameservers`,
`set_nameservers`, `connection_ready?`, and as a fallback in `network_hidden?`.

**CLI commands:** `info`, `status`, `nameservers`, `connect`, `qr`.

**Details:** Empty values and NetworkManager's `--` placeholder are normalized to `nil`.

---

## `nmcli connection show <profile>`

**Description:** Read full connection-profile state, including configured and runtime DNS settings.

**Dynamic values:** `<profile>` — active profile name or resolved connection name.

**Base model methods:** `nameservers_from_connection`, `nameservers`.

**CLI commands:** `nameservers`, `info`.

**Details:** Parses both static fields (`ipv4.dns[1]`) and observed runtime fields (`IP4.DNS[1]`),
splitting only on the first colon so IPv6 addresses stay intact.

---

## `nmcli --get-values <field> connection show <profile>`

**Description:** Read a single DNS-related connection-profile property.

**Dynamic values:** `<field>` — one of `ipv4.dns`, `ipv4.ignore-auto-dns`, `ipv6.dns`,
`ipv6.ignore-auto-dns`. `<profile>` — active profile name.

**Base model methods:** `connection_property_value`, `dns_configuration_snapshot`, `set_nameservers`.

**CLI commands:** `nameservers clear`, `nameservers <IP ...>`.

**Details:** Captured before DNS mutation so a failed reactivation can restore the exact original values.

---

## `nmcli connection modify <profile> <dns-field> <value>`

**Description:** Set or clear DNS-related fields on a connection profile.

**Dynamic values:** `<profile>` — active profile name. `<dns-field>` — one of `ipv4.dns`,
`ipv4.ignore-auto-dns`, `ipv6.dns`, `ipv6.ignore-auto-dns`. `<value>` — a space-separated address list,
`yes`/`no`, or an empty string.

**Base model methods:** `dns_configuration_modify_commands`, `set_nameservers`, `restore_dns_configuration`.

**CLI commands:** `nameservers clear`, `nameservers <IP ...>`.

**Details:** DNS is configured per NetworkManager profile, not directly on the interface. IPv4/IPv6
values are split by address family, and setting static DNS also toggles the matching
`ignore-auto-dns` field.

---

## `nmcli dev disconnect <interface>`

**Description:** Disconnect the Wi-Fi interface without disabling the radio.

**Dynamic values:** `<interface>` — `wifi_interface`.

**Base model methods:** `_disconnect` (via `DisconnectManager`).

**CLI commands:** `disconnect`.

**Details:** Exit status `6` is treated as a no-op success — NetworkManager returns it when there's no
active connection to tear down.

---

## `nmcli -t -f 802-11-wireless.hidden connection show <profile>`

**Description:** Check whether a profile is configured for a hidden network.

**Dynamic values:** `<profile>` — active profile name, falling back to the connected SSID if no active
profile name is available.

**Base model methods:** `network_hidden?`.

**CLI commands:** `qr` (sets the Wi-Fi QR payload's `H:true` / `H:false` field), `info`.

---

## `ip link show <interface>`

**Description:** Read link-layer details for the interface, including its MAC address.

**Dynamic values:** `<interface>` — `wifi_interface`.

**Base model methods:** `mac_address`.

**CLI commands:** `info`, `status`.

**Details:** MAC address is read from the token following `link/ether`.

---

## `ip -4 addr show <interface>` / `ip -6 addr show <interface>`

**Description:** Read IPv4 / IPv6 addresses assigned to the interface.

**Dynamic values:** `<interface>` — `wifi_interface`.

**Base model methods:** `_ipv4_addresses` / `_ipv6_addresses`, `interface_ip_addresses` (private,
parameterized by IP version).

**CLI commands:** `info`.

**Details:** Output is parsed by `IPAddressExtractor`, which strips the CIDR suffix and any IPv6 zone ID.

---

## `ip route show default`

**Description:** Identify the interface used for the default route.

**Dynamic values:** none

**Base model methods:** `default_interface`.

**CLI commands:** `info`.

**Details:** The first default-route row is tokenized and the value following `dev` is returned.

---

## `xdg-open <resource-url>`

**Description:** Open a configured project or documentation resource in the desktop environment.

**Dynamic values:** `<resource-url>` — URL selected by `ResourceManager` from a resource code.

**Base model methods:** `open_resource`, `open_resources_by_codes` (via `ResourceManager`).

**CLI commands:** `ropen`.

**Details:** Unlike the three core Wi-Fi utilities, `xdg-open` availability is not checked by
`validate_os_preconditions` — only when `ropen` actually runs.

---

## `qrencode -t <type> -o - <qr-string>`

**Description:** Render a Wi-Fi QR code to stdout as ANSI, PNG, SVG, or EPS.

**Dynamic values:** `<type>` — `ANSI`, `PNG`, `SVG`, or `EPS`. `<qr-string>` — generated Wi-Fi QR payload
(SSID, password, security type, hidden flag).

**Base model methods:** `render_qr_code`, `print_qr_code`, `generate_qr_code`,
`QrCodeGenerator#render_qr_data` (helper).

**CLI commands:** `qr`.

**Details:** Availability is checked by scanning `PATH` immediately before use, not at startup. PNG
output is captured as binary stdout; verbose logging is suppressed for this call via `log_stdout: false`.

---

## Non-`run_command` process spawns (OS-agnostic, not Ubuntu-specific)

These two are launched with `Process.spawn` directly from `NetworkConnectivityTester` and
`CaptivePortalChecker`, bypassing `BaseModel#run_command` entirely. They're shared across all platforms
rather than being part of the Ubuntu model, but they are still OS command invocations worth documenting
here since they run on every `info`/`status`/`ci` call on Ubuntu too.

### `<ruby> network_connectivity_probe_helper.rb <mode> <items-json> <timeout>`

**Description:** Spawn a helper process for TCP or DNS connectivity probes.

**Dynamic values:** `<ruby>` — `RbConfig.ruby`. `<mode>` — TCP or DNS probe mode. `<items-json>` —
JSON-encoded endpoint/domain list. `<timeout>` — overall timeout in seconds.

**Base model methods:** `internet_tcp_connectivity?`, `dns_working?`, `internet_connectivity_state`,
`status_line_data`, `wifi_info`, `till internet_on` / `till internet_off`.

**CLI commands:** `ci`, `info`, `status`, `till internet_on`, `till internet_off`.

**Details:** The helper process isolates network probes and reports structured results back over a pipe.

### `<ruby> captive_portal_probe_helper.rb <url> <expected-code> <expected-body>`

**Description:** Spawn a helper process for captive-portal detection.

**Dynamic values:** `<ruby>` — `RbConfig.ruby`. `<url>` — configured captive-portal check endpoint.
`<expected-code>` / `<expected-body>` — expected HTTP status/body marker.

**Base model methods:** `captive_portal_login_required`, `internet_connectivity_state`,
`status_line_data`, `wifi_info`, `till internet_on` / `till internet_off`.

**CLI commands:** `ci`, `info`, `status`, `till internet_on`, `till internet_off`.

**Details:** Runs only after the TCP/DNS probes above already have enough evidence to make a
captive-portal check meaningful.

---

## Non-command file fallback: `/etc/resolv.conf`

**Description:** Read resolver nameservers when the active NetworkManager profile exposes no DNS data.

**Dynamic values:** none

**Base model methods:** `nameservers_using_resolv_conf` (private), `nameservers`.

**CLI commands:** `nameservers`, `info`.

**Details:** A direct `File.readlines` call, not an OS command. Lines beginning with `nameserver ` are
parsed and the last token on the line is returned.

---

## Notes on command construction

- All commands above are passed to `BaseModel#run_command` as arrays, e.g.
  `['nmcli', 'radio', 'wifi', 'on']`.
- `run_command` delegates to `CommandExecutor#run_command_using_args`, which validates that the argument
  is an `Array` and refuses shell strings — dynamic values (SSIDs, passwords, profile names) are never
  shell-interpolated.
- Timeouts, stdout logging, and error-raising behavior are configured per call via keyword arguments
  (`raise_on_error:`, `timeout_in_secs:`, `log_stdout:`).
- The two Ruby probe helpers and the `/etc/resolv.conf` read are the only exceptions to the
  "everything goes through `run_command`" rule — worth remembering if this doc is used to reason about
  command-injection surface.
