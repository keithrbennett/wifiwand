# macOS OS Commands Reference

This document outlines the shell commands used by wifi-wand on macOS.

Notes:
- macOS differentiates network service labels (e.g., "Wi-Fi") from interface devices (e.g., `en0`). `wifi-wand` captures both so each command receives the argument it expects.
- Several commands warm detection caches that later operations reuse; listed CLI commands indicate where users may observe the behavior.

## `networksetup`

`networksetup` is the built-in macOS utility for managing network services and Wi-Fi radios.

### `networksetup -listallhardwareports`
- Description: Lists every hardware port so the Wi-Fi service name and interface device can be discovered.
- Dynamic Values: None
- Base Model Method(s): `detect_wifi_service_name`, `detect_wifi_interface_using_networksetup`, `detect_wifi_interface`
- CLI Command(s): Internal (interface/service detection shared by most commands)
- Helpful Info: Populates cached `wifi_service_name`/`wifi_interface` values to avoid repeated probing.

### `networksetup -listpreferredwirelessnetworks <interface>`
- Description: Retrieves the saved (preferred) network SSIDs for the specified interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `preferred_networks`, `is_wifi_interface?`
- CLI Command(s): `pr` (preferred networks), `pa` (preferred password lookup), `f` (forget), `co` (connect via saved password path)
- Helpful Info: The first line of output is dropped and results are sorted case-insensitively before use.

### `networksetup -getairportpower <interface>`
- Description: Reports whether Wi-Fi power is on for the interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_on?`
- CLI Command(s): `w` (wifi status), plus guard checks in `a`, `co`, `cy`, `i`, and `na`
- Helpful Info: The command returns strings ending with `On`/`Off`; a regex matches the `On` suffix.

### `networksetup -setairportpower <interface> on`
- Description: Enables Wi-Fi power for the interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_on`
- CLI Command(s): `on`, `cy`
- Helpful Info: After enabling, the model re-checks `wifi_on?`; failure triggers `WifiEnableError`.

### `networksetup -setairportpower <interface> off`
- Description: Disables Wi-Fi power for the interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `wifi_off`
- CLI Command(s): `of`, `cy`
- Helpful Info: Post-command verification raises `WifiDisableError` if the radio remains on.

### `networksetup -setairportnetwork <interface> <network_name> [password]`
- Description: Connects to a Wi-Fi network using the built-in Network Setup tool.
- Dynamic Values: `interface` (from `wifi_interface`), `network_name`, `password` (optional)
- Base Model Method(s): `os_level_connect_using_networksetup`, `_connect`
- CLI Command(s): `co`
- Helpful Info: `networksetup` exits with code 0 even on failure; the implementation inspects the combined output for error patterns and raises on authentication failures.

### `sudo networksetup -removepreferredwirelessnetwork <interface> <network_name>`
- Description: Removes a saved network profile from macOS preferences.
- Dynamic Values: `interface` (from `wifi_interface`), `network_name`
- Base Model Method(s): `remove_preferred_network`
- CLI Command(s): `f`
- Helpful Info: Requires sudo privileges; absence of privileges surfaces as an `OsCommandError` to the user.

### `networksetup -setdnsservers <service_name> empty`
- Description: Clears custom DNS servers for the Wi-Fi service so DHCP-provided values are used.
- Dynamic Values: `service_name` (from `wifi_service_name`)
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na` (clear)
- Helpful Info: The `empty` token is specific to macOS; successful execution resets both IPv4 and IPv6 settings to automatic.

### `networksetup -setdnsservers <service_name> <nameserver...>`
- Description: Assigns one or more DNS servers to the Wi-Fi service.
- Dynamic Values: `service_name` (from `wifi_service_name`), `nameservers` (validated IPv4/IPv6 strings)
- Base Model Method(s): `set_nameservers`
- CLI Command(s): `na` (set)
- Helpful Info: Inputs are checked with `IPAddr`; any invalid address triggers `InvalidIPAddressError` before the OS call.

### `networksetup -getdnsservers <service_name>`
- Description: Reads the DNS servers configured for the Wi-Fi service.
- Dynamic Values: `service_name` (from `wifi_service_name`)
- Base Model Method(s): `nameservers_using_networksetup`
- CLI Command(s): `na` (diagnostics), `i` (info aggregation)
- Helpful Info: The method normalizes Apple's “There aren't any DNS Servers set...” message to an empty list.

## `system_profiler`

`system_profiler` emits structured JSON snapshots of hardware and Wi-Fi state that the model parses.

### `system_profiler -json SPNetworkDataType`
- Description: Produces JSON metadata describing network services and interfaces.
- Dynamic Values: None
- Base Model Method(s): `detect_wifi_interface`
- CLI Command(s): Internal (fallback interface discovery used when `networksetup` detection fails)
- Helpful Info: JSON is parsed to locate entries keyed by the detected Wi-Fi service name.

### `system_profiler -json SPAirPortDataType`
- Description: Generates detailed Wi-Fi telemetry including SSIDs, signal levels, and security information.
- Dynamic Values: None
- Base Model Method(s): `airport_data`, `_available_network_names`, `_connected_network_name`, `connection_security_type`, `network_hidden?`
- CLI Command(s): `a` (available networks), `i` (info), `ne` (network name), `qr` (QR code generation)
- Helpful Info: The model caches parsed results and extracts signal strength noise ratios to sort networks by quality.

## `security`

The `security` tool integrates with the macOS Keychain to retrieve stored Wi-Fi credentials.

### `security find-generic-password -D "AirPort network password" -a <network_name> -w`
- Description: Retrieves a stored Wi-Fi password from the user's login keychain.
- Dynamic Values: `network_name`
- Base Model Method(s): `_preferred_network_password`
- CLI Command(s): `pa`, `co`, `qr`
- Helpful Info: Exit codes map to custom exceptions (e.g., 45 → `KeychainAccessDeniedError`); a missing item returns `nil` without raising.

## `ipconfig`

`ipconfig` supplies interface IP addressing details for macOS network adapters.

### `ipconfig getifaddr <interface>`
- Description: Obtains the IPv4 address assigned to the Wi-Fi interface.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `_ip_address`
- CLI Command(s): `i`, `s` (status ticker), `log`
- Helpful Info: Exit status 1 is treated as “no address” and converted to `nil`; other failures propagate.

## `ifconfig`

`ifconfig` exposes interface statistics and connection controls used as CoreWLAN fallbacks.

### `sudo ifconfig <interface> disassociate`
- Description: Disconnects the interface from its current Wi-Fi network when Swift/CoreWLAN is unavailable.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `_disconnect`
- CLI Command(s): `d`
- Helpful Info: Falls back to `ifconfig <interface> disassociate` without sudo if the privileged form fails; both invocations suppress exceptions (`raise_on_error = false`) so alternate paths can run.

### `ifconfig <interface>`
- Description: Retrieves interface details to extract the MAC address.
- Dynamic Values: `interface` (from `wifi_interface`)
- Base Model Method(s): `mac_address`
- CLI Command(s): `i`, `s`, `log`
- Helpful Info: The implementation scans for the `ether` line and returns the following token in lowercase.

## `scutil`

`scutil` reveals the System Configuration DNS view, including scoped resolvers.

### `scutil --dns`
- Description: Produces the system-wide DNS configuration, including per-interface scopes.
- Dynamic Values: None
- Base Model Method(s): `nameservers_using_scutil`, `nameservers`
- CLI Command(s): `na` (get), `i`, `s`, `log`
- Helpful Info: Lines starting with `nameserver[` are deduplicated so repeated entries do not surface in CLI output.

## `swift`

Swift helpers leverage the CoreWLAN framework for rich Wi-Fi control when the toolchain is available.

### `swift -e 'import CoreWLAN'`
- Description: Verifies that the Swift toolchain and CoreWLAN framework are available.
- Dynamic Values: None
- Base Model Method(s): `swift_and_corewlan_present?`
- CLI Command(s): `co`, `d`, `qr`
- Helpful Info: Verbose mode prints actionable guidance for exit statuses 127 (Swift missing) and 1 (CoreWLAN unavailable).

### `swift swift/WifiNetworkConnector.swift <network_name> [password]`
- Description: Uses a Swift helper to connect via CoreWLAN when available.
- Dynamic Values: `swift_filespec` (absolute path to the helper), `network_name`, `password` (optional)
- Base Model Method(s): `run_swift_command`, `os_level_connect_using_swift`, `_connect`
- CLI Command(s): `co`
- Helpful Info: The CoreWLAN path is attempted before the `networksetup` fallback; specific CoreWLAN error codes trigger retries with the legacy command.

### `swift swift/WifiNetworkDisconnector.swift`
- Description: Invokes a Swift helper to disconnect using CoreWLAN.
- Dynamic Values: `swift_filespec` (absolute path to the helper)
- Base Model Method(s): `_disconnect`
- CLI Command(s): `d`
- Helpful Info: Failure automatically falls back to the `ifconfig disassociate` path described above.

## `route`

`route` interrogates the kernel routing table to discover gateway interfaces.

### `route -n get default`
- Description: Queries the kernel routing table for the default route information.
- Dynamic Values: None
- Base Model Method(s): `default_interface`
- CLI Command(s): `i`, `s`, `log`
- Helpful Info: The command is executed with `raise_on_error = false`; missing routes simply yield `nil`.

## `sw_vers`

`sw_vers` reports the macOS product version for diagnostics and compatibility checks.

### `sw_vers -productVersion`
- Description: Returns the current macOS version string.
- Dynamic Values: None
- Base Model Method(s): `detect_macos_version`
- CLI Command(s): Internal (used for diagnostics and verbose reporting)
- Helpful Info: Errors are suppressed in non-verbose mode; verbose mode prints a warning when the OS version cannot be determined.

## `open`

The `open` utility launches macOS applications and resources via the default handler.

### `open -a <application_name>`
- Description: Launches a macOS application by name.
- Dynamic Values: `application_name`
- Base Model Method(s): `open_application`
- CLI Command(s): Currently none (API surface for library consumers)
- Helpful Info: Relies on macOS default application lookup; failures raise `OsCommandError` to callers.

### `open <resource_url>`
- Description: Opens a URL or file using the default handler.
- Dynamic Values: `resource_url`
- Base Model Method(s): `open_resource`
- CLI Command(s): `ro`
- Helpful Info: Used by the resource manager to open documentation or support links in the user’s browser.

## `qrencode`

`qrencode` renders Wi-Fi credentials into shared QR codes for other devices.

### `qrencode -o <file> <wifi_qr_string>`
- Description: Renders the Wi-Fi credentials QR code to an image file.
- Dynamic Values: `file` (from CLI/filespec), `wifi_qr_string` (escapes SSID/password/hidden flags)
- Base Model Method(s): `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_file`
- CLI Command(s): `qr` (file output)
- Helpful Info: Output type switches to SVG/EPS when the filename extension matches; overwrite prompts run before the command executes.

### `qrencode -t ANSI <wifi_qr_string>`
- Description: Emits an ANSI-art QR code to stdout.
- Dynamic Values: `wifi_qr_string`
- Base Model Method(s): `BaseModel#generate_qr_code` via `Helpers::QrCodeGenerator#run_qrencode_text`
- CLI Command(s): `qr -`
- Helpful Info: In non-interactive CLI mode the ANSI output streams directly to stdout; interactive shells return the string so callers can `puts` it manually.
