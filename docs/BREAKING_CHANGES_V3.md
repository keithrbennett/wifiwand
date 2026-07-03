# Version 3 Breaking Changes

This document is the canonical upgrade and migration guide for breaking changes
introduced in version 3.0.

For a broader summary of version 3 improvements, architecture changes, and
non-breaking additions, see [Version 2.x to 3.0 Code Base Changes](CHANGELOG_V2_TO_V3.md).

> **Action required for all users:** The primary executable has been renamed
> from `wifi-wand` to `wifiwand`. Update every script, alias, and shell
> function that calls `wifi-wand`. The old name still works but prints a
> deprecation warning to stderr. See the [Executable renamed](#executable-renamed)
> section below.

## Breaking Changes

### Executable renamed

#### `wifi-wand` → `wifiwand`

The command you type has changed. Every invocation of `wifi-wand` must be
updated to `wifiwand`:

```bash
# Old
wifi-wand info
wifi-wand co MyNetwork mypassword
wifi-wand shell

# New
wifiwand info
wifiwand co MyNetwork mypassword
wifiwand shell
```

The macOS setup helper has changed in the same way:

```bash
# Old
wifi-wand-macos-setup

# New
wifiwand-macos-setup
```

**The gem name on RubyGems is unchanged.** Install and upgrade as before:

```bash
gem install wifi-wand
```

**Backward compatibility:** The old `wifi-wand` and `wifi-wand-macos-setup`
commands remain installed as thin wrappers. They run the new executable
transparently, but print a deprecation notice to stderr on every invocation:

```
wifi-wand: deprecated — please use 'wifiwand' instead.
```

Update all scripts, shell aliases, `.zshrc`/`.bashrc` functions, and cron
entries that call `wifi-wand` before the deprecated wrappers are eventually
removed in a future major release.

##### Migration checklist

- [ ] Shell aliases — search `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`
- [ ] Shell functions that call `wifi-wand`
- [ ] Cron jobs and launchd plists
- [ ] CI/CD scripts
- [ ] README or documentation in your own projects

### Output format flags changed

#### Canonical output format codes and long names

The `--output-format` option now accepts exactly one short code and one long
name per format. No other spellings are accepted.

| Code | Long name       | Description                                         |
|------|-----------------|-----------------------------------------------------|
| `a`  | `amazing_print` | AmazingPrint colored output                         |
| `i`  | `inspect`       | Ruby `object.inspect`                               |
| `j`  | `json`          | Compact JSON                                        |
| `J`  | `pretty_json`   | Multi-line, indented JSON                           |
| `p`  | `puts`          | Ruby `puts` semantics (arrays: one element per line)|
| `P`  | `pretty_print`  | Ruby `PP.pp` output                                 |
| `y`  | `yaml`          | YAML                                                |

Both the short code and the long name are accepted:

```bash
wifiwand -o j info
wifiwand -o json info   # equivalent
wifiwand -o J info
wifiwand -o pretty_json info   # equivalent
```

Noncanonical spellings — including hyphens (`pretty-json`), old aliases
(`awesome_print`, `ap`), and uppercase variants of lowercase codes (`Y`, `A`,
`I`) — are rejected with a `ConfigurationError`.

#### Pretty JSON moved to `-o J`

The noninteractive `--output-format` codes have changed so each human-oriented
Ruby formatter has a distinct option.

| Format | Old flag | New flag |
|--------|----------|----------|
| Compact JSON | `-o j` | `-o j` |
| Pretty JSON | `-o k` | `-o J` |
| Puts | `-o p` | `-o p` |
| Pretty print | not available | `-o P` |
| Amazing print | default human output only | `-o a` |
| Inspect | `-o i` | `-o i` |
| YAML | `-o y` | `-o y` |

The `-o p` flag still means plain `puts` output. Scripts that depended on
`-o p` for unquoted scalar values can keep using it:

```bash
state="$(wifiwand -o p ci)"
```

Use `-o J` when you want multi-line, indented JSON:

```bash
wifiwand -o J info
```

Use `-o P` when you want Ruby pretty print output:

```bash
wifiwand -o P info
```

#### Amazing Print color follows stdout

The `-o a` formatter now lets `amazing_print` decide whether to emit ANSI color instead of forcing plain text.
It uses color when stdout is a terminal and plain text when output is piped or redirected. Pipe through `tee`
if you want terminal-readable plain output while also saving or forwarding it:

```bash
wifiwand -o a info | tee wifi-info.txt
```

### Pretty output dependency changed

#### `awesome_print` replaced by `amazing_print`

WifiWand now depends on `amazing_print` for human-readable object formatting.
Ruby consumers that indirectly relied on WifiWand to make `awesome_print`
available must add their own direct `awesome_print` dependency or migrate to
`amazing_print`.

### Ruby require paths renamed

#### Library require paths now use `wifi_wand`

The Ruby library entry point and sub-require paths now use snake_case file names
instead of the gem's hyphenated command name.

```ruby
# Old
require 'wifi-wand'
require 'wifi-wand/models/ubuntu_model'
require 'wifi-wand/models/mac_os_model'

# New
require 'wifi_wand'
require 'wifi_wand/platforms/ubuntu/model'
require 'wifi_wand/platforms/mac/model'
```

The gem name is unchanged: install with `gem install wifi-wand`. The CLI
executable is now `wifiwand` (see [Executable renamed](#executable-renamed)).

### macOS helper runtime naming

#### Legacy helper require path removed

The legacy runtime helper file
`wifi-wand/mac_helper/mac_os_wifi_auth_helper` is no longer shipped.

Code that previously did a direct require such as:

```ruby
require 'wifi-wand/mac_helper/mac_os_wifi_auth_helper'
```

must now require the new primary runtime entry point instead:

```ruby
require 'wifi_wand/platforms/mac/helper/bundle'
```

#### Migration

- old require path: `wifi-wand/mac_helper/mac_os_wifi_auth_helper`
- new require path: `wifi_wand/platforms/mac/helper/bundle`

The legacy constant name `WifiWand::MacOsWifiAuthHelper` no longer resolves.
Load `wifi_wand/platforms/mac/helper/bundle` and use the supported
runtime names directly:

- `WifiWand::Platforms::Mac::Helper::Bundle`
- `WifiWand::Platforms::Mac::Helper::Client`
- `WifiWand::Platforms::Mac::Helper::Installer`

The older nested constants `WifiWand::MacOsHelperBundle::Client` and
`WifiWand::MacOsHelperBundle::Installer` are also no longer provided.

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

- old: `wifiwand conn MyNet`
- new: `wifiwand co MyNet` or `wifiwand connect MyNet`

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

The companion captive-portal API is now `captive_portal_login_required`, returning:

- `:yes`
- `:no`
- `:unknown`

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

`WifiWand` no longer assumes that WiFi being off means Internet connectivity is
unavailable, because connectivity may come from another interface such as
Ethernet.

- The `ci` command can now report Internet connectivity even when WiFi is off.
- DNS, TCP, and captive-portal signals are tracked separately in the broader
  connectivity flow.

### Local IP Address Reporting

#### Local IPv4 address reporting uses `ipv4_addresses`

The local IPv4 field in `info` has been renamed from `ip_address` to
`ipv4_addresses`. `info["ipv4_addresses"]` and `BaseModel#ipv4_addresses` now
return arrays of IPv4 addresses instead of a single string or `nil`.

This lets WifiWand report every IPv4 address assigned to the WiFi interface.
Interfaces with no assigned IPv4 address now report an empty array.
`BaseModel#ip_address` has been removed; callers must use
`BaseModel#ipv4_addresses`.

Custom `BaseModel` subclasses must now implement `_ipv4_addresses` and
`_ipv6_addresses`. Existing subclasses that implemented `_ip_address` must move
their IPv4 implementation to `_ipv4_addresses`; `_ip_address` is no longer part
of the subclass contract.

##### Migration

```ruby
# Old
info['ip_address'] #=> '192.168.1.100'

# New
info['ipv4_addresses'] #=> ['192.168.1.100']

# Old, no IPv4 address assigned
info['ip_address'] #=> nil

# New, no IPv4 address assigned
info['ipv4_addresses'] #=> []
```

Callers that only need one address can use `info['ipv4_addresses'].first`.
Callers that previously used nil checks should use `info['ipv4_addresses'].any?`
when testing whether an IPv4 address is present. Callers that display or log
the value should handle multiple addresses.

#### Local IPv6 addresses are now reported

The `info` command now also reports local IPv6 addresses assigned to the WiFi
interface. Use the `ipv6_addresses` field, which always returns an array.

```ruby
info['ipv6_addresses'] #=> ['fe80::1', '2001:db8::100']

# No IPv6 address assigned
info['ipv6_addresses'] #=> []
```

Callers that need both address families should read `info['ipv4_addresses']`
and `info['ipv6_addresses']` separately instead of treating `ip_address` as a
generic local-address field.

### Public IP Reporting

#### Public IP info removed from `info`

This is a breaking change in both location and data shape.

The `info` command no longer returns `public_ip`. The entire
`info["public_ip"]` container has been removed. Public IP lookup is now an
explicit CLI feature exposed through `public_ip` and its short alias `pi`.

##### What changed

| Old | New |
|-----|-----|
| `info["public_ip"]` | `wifiwand public_ip` / `wifiwand pi` |
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
- new, both fields: `wifiwand public_ip` or `wifiwand pi`
- new, address only: `wifiwand public_ip address` or `wifiwand pi a`
- new, country only: `wifiwand public_ip country` or `wifiwand pi c`

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

### Library Entry Point

#### `WifiWand.create_model` now strictly enforces Hash options

The `WifiWand.create_model` method (and the underlying `BaseModel.create_model`
and `WifiWand::Platforms::Selector.create_model_for_current_os`) now strictly validates that
the `options` argument is a `Hash`.

Previously, these methods were more permissive, which allowed passing objects
like `OpenStruct`. They now raise an `ArgumentError` if a non-Hash is provided.

##### Migration

If you were passing an `OpenStruct` or another custom object, convert it to a
`Hash` before calling `create_model`.

```ruby
# Old
options = OpenStruct.new(verbose: true)
model = WifiWand.create_model(options)

# New
options = { verbose: true }
model = WifiWand.create_model(options)
```

### CLI and Configuration Changes

#### Log command output is now JSON Lines

The `log` command previously wrote human-readable bracketed lines such as:

```text
[2025-10-28T19:44:19-04:00] Current state: WiFi on, connected to MyNetwork, internet available
[2025-10-28T19:45:50-04:00] Connected to MyNetwork
```

It now emits JSON Lines (one JSON object per line):

```json
{"timestamp":"2025-10-28T19:44:19-04:00","event":"current_state","wifi":true,"connection":"connected","network":"MyNetwork","internet":"available"}
{"timestamp":"2025-10-28T19:45:50-04:00","event":"connected","network":"MyNetwork"}
```

Scripts that grep or parse the old bracketed format must be updated. The `event`
field identifies each line type; see `docs/LOGGING.md` for the full event schema.

#### Global `--verbose` now requires an explicit boolean value

The global verbose option now follows the same boolean parsing contract as the
global `--utc` option. The old toggle-style forms no longer work.

| Old usage | New usage |
|-----------|-----------|
| `wifiwand -v info` | `wifiwand -v true info` |
| `wifiwand --verbose info` | `wifiwand --verbose true info` |
| `wifiwand --no-verbose info` | `wifiwand --verbose false info` |
| `wifiwand --no-v info` | `wifiwand -v false info` |

Accepted true values are `true`, `t`, `yes`, `y`, and `+`. Accepted false
values are `false`, `f`, `no`, `n`, and `-`.

Inline forms are also accepted:

```bash
wifiwand --verbose=true info
wifiwand -vfalse info
```

When setting defaults through `WIFIWAND_OPTS`, include the boolean value:

```bash
export WIFIWAND_OPTS="--verbose true"
```

The `log` command's `--verbose-logs` option also uses explicit boolean
values.

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
- Removed `fancy_print`. Amazing Print is now a required gem, so there is no
  need for a separate fallback.
- The `-s` / `--shell` command-line option has been replaced with a `shell`
  command.
- All environment variables have been renamed to use the `WIFIWAND_` prefix
  (for example `WIFIWAND_VERBOSE` and `WIFIWAND_OPTS`).
- Removed the `l` / `ls_avail_nets` command; it is no longer operational.
- The `--hook` option for the `log` subcommand has been removed. The hook
  execution feature was incomplete and never properly tested.
