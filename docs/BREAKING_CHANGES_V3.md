# Version 3 Breaking Changes

This document is the canonical upgrade and migration guide for breaking changes
introduced in version 3.0.

For a broader summary of version 3 improvements, architecture changes, and
non-breaking additions, see [Version 2.x to 3.0 Code Base Changes](CHANGELOG_V2_TO_V3.md).

## Breaking Changes

### Verbose API naming

#### `verbose?` and `verbose=` are now the only supported forms

The public `verbose` and `verbose_mode` aliases have been removed from the
library-facing objects that exposed them.

Use:

- `verbose?` to read the flag
- `verbose=` to update the flag

This makes the API follow standard Ruby predicate naming instead of supporting
multiple reader spellings for the same boolean state.

### Error constructor keywords

Several `WifiWand::Error` subclasses that previously accepted multiple
positional constructor arguments now require keyword arguments instead.

This change makes the call sites self-describing and removes ambiguous
argument ordering from the error API.

#### Migration

```ruby
# Old
raise WifiWand::NetworkConnectionError.new('MyNet', 'timed out')
raise WifiWand::WaitTimeoutError.new(:associated, 5)
raise WifiWand::CommandExecutor::OsCommandError.new(1, 'nmcli', 'boom')

# New
raise WifiWand::NetworkConnectionError.new(network_name: 'MyNet', reason: 'timed out')
raise WifiWand::WaitTimeoutError.new(action: :associated, timeout: 5)
raise WifiWand::CommandExecutor::OsCommandError.new(exitstatus: 1, command: 'nmcli', text: 'boom')
```

### CLI Command Matching

#### Partial command abbreviations removed

CLI commands no longer accept arbitrary intermediate-length abbreviations
between the short form and long form.

Only these forms are now valid:

- the exact short form, such as `co`
- the exact long form, such as `connect`

Intermediate partial spellings such as `con`, `conn`, and `connec` are now
treated as invalid commands and follow the normal invalid-command behavior.

##### Migration

- old: `wifi-wand conn MyNet`
- new: `wifi-wand co MyNet` or `wifi-wand connect MyNet`

### Connectivity API

#### `connected_to_internet?` replaced by `internet_connectivity_state`

The old boolean-style `connected_to_internet?` API has been removed and
replaced by `internet_connectivity_state`.

| Old | New |
|-----|-----|
| `true` | `:reachable` |
| `false` | `:unreachable` |
| `nil` | `:indeterminate` |

This change makes uncertainty explicit. `:indeterminate` means TCP and DNS
worked, but captive-portal checks could not determine whether the network is
actually open Internet or intercepted.

The companion captive-portal API is now `captive_portal_state`, returning:

- `:free`
- `:present`
- `:indeterminate`

##### Migration

```ruby
# Old
model.connected_to_internet? == true

# New
model.internet_connectivity_state == :reachable
```

Callers should replace boolean checks with explicit state comparisons and
handle `:indeterminate` separately where appropriate.

#### CLI `ci` output now reports explicit state values

The `ci` command no longer represents connectivity as `true` / `false`.

- Human-readable output: `Internet connectivity: reachable`
- Plain output: `reachable`, `unreachable`, or `indeterminate`
- JSON output: `"reachable"`, `"unreachable"`, or `"indeterminate"`

#### WiFi-off connectivity behavior changed

`wifi-wand` no longer assumes that WiFi being off means Internet connectivity is
unavailable, because connectivity may come from another interface such as
Ethernet.

- The `ci` command can now report Internet connectivity even when WiFi is off.
- DNS, TCP, and captive-portal signals are tracked separately in the broader
  connectivity flow.

### Public IP Reporting

#### Public IP info removed from `info`

This is a breaking change in both location and data shape.

The `info` command no longer returns `public_ip`. The entire
`info["public_ip"]` container has been removed. Public IP lookup is now an
explicit CLI feature exposed through `public_ip` and its short alias `pi`.

##### What changed

| Old | New |
|-----|-----|
| `info["public_ip"]` | `wifi-wand public_ip` / `wifi-wand pi` |
| nested `public_ip` object inside `info` | dedicated command result |
| broader unauthenticated IPinfo payload | narrower result with only `address` and `country` |

##### Fields no longer provided

The old `info["public_ip"]` payload could include these fields, which are no
longer returned by the new command:

- `hostname`
- `city`
- `region`
- `loc`
- `org`
- `postal`
- `timezone`
- `readme`

The new command supports only:

- `address`
- `country`

##### Migration

- old: `info["public_ip"]`
- new, both fields: `wifi-wand public_ip` or `wifi-wand pi`
- new, address only: `wifi-wand public_ip address` or `wifi-wand pi a`
- new, country only: `wifi-wand public_ip country` or `wifi-wand pi c`

##### Current result shape

```json
{
  "address": "203.0.113.5",
  "country": "TH"
}
```

This change keeps `info` focused on local network state and makes external
public-IP lookup explicit.

### `till` Wait States

#### `till` wait-state vocabulary redesigned

The `till` command now uses an explicit, unambiguous vocabulary. The old state
names `conn`, `disc`, `on`, and `off` have been removed.

Why this changed: `conn` checked full Internet reachability
(`internet_connectivity_state == :reachable`), not WiFi association. That made
it easy to confuse "joined the WiFi network" with "has Internet access". The
new vocabulary separates those meanings.

##### New state names

| State | Meaning |
|-------|---------|
| `wifi_on` | WiFi hardware is powered on |
| `wifi_off` | WiFi hardware is powered off |
| `associated` | WiFi is associated with an SSID (WiFi layer, not Internet) |
| `disassociated` | WiFi is not associated with any SSID |
| `internet_on` | Internet connectivity state is reachable |
| `internet_off` | Internet connectivity state is unreachable |

`internet_connectivity_state` can also be `:indeterminate` when TCP and DNS
succeed but captive-portal checks cannot determine whether the Internet is
actually reachable. There is no dedicated `till` target for this state:
`internet_on` matches only `:reachable`, and `internet_off` matches only
`:unreachable`.

##### Migration table

| Old usage | New usage |
|-----------|-----------|
| `till on` | `till wifi_on` |
| `till off` | `till wifi_off` |
| `till conn` | `till internet_on` or `till associated` |
| `till disc` | `till internet_off` or `till disassociated` |

Using a removed name now raises an `ArgumentError` with a clear message listing
the valid state names.

##### Internal behavior changes

- Connection flows now wait for WiFi association (`:associated`) rather than
  Internet reachability.
- Restore flows wait for WiFi power state (`:wifi_on` / `:wifi_off`) as
  appropriate.

### CLI and Configuration Changes

- `WifiWand::Main#parse_command_line` has been removed from the public API.
  If you parsed CLI arguments programmatically, instantiate
  `WifiWand::CommandLineParser` and call `#parse` instead.
- `cycle_network` now toggles WiFi state twice regardless of starting state.
  Previously it unconditionally did off, then on.
- Removed macOS Speedtest application launch support. The web site is still
  available via the `ro spe` command.
- Removed the public `open_application` model API. This helper was a thin
  wrapper around platform launch commands, was not part of the CLI contract,
  and was not central to WiFi management. If similar behavior is needed again,
  it can return as a private OS-specific helper instead of a required public
  model method.
- Removed `fancy_print`. Awesome Print is now a required gem, so there is no
  need for a separate fallback.
- The `-s` / `--shell` command-line option has been replaced with a `shell`
  subcommand.
- All environment variables have been renamed to use the `WIFIWAND_` prefix
  (for example `WIFIWAND_VERBOSE` and `WIFIWAND_OPTS`).
- Removed the `l` / `ls_avail_nets` command; it is no longer operational.
- The `--hook` option for the `log` subcommand has been removed. The hook
  execution feature was incomplete and never properly tested.
