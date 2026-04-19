# Version 2.x to 3.0 Code Base Changes

This document summarizes the major changes introduced in version 3.0 compared
to version 2.x.

Version 3.0 also includes some intentional API and implementation cleanup.
Part of the motivation for these changes was to trim accidental surface area,
remove features that were not pulling their weight, and keep the codebase
smaller and easier to reason about before broader release.

## Breaking Changes

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
client.connected_to_internet? == true

# New
client.internet_connectivity_state == :reachable
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

## Major Features and Improvements

### Ubuntu Linux Support

- Added full Ubuntu Linux support alongside existing macOS functionality.
- Implemented `UbuntuModel` class using `nmcli`, `iw`, and `ip` command-line
  tools.
- Created Ubuntu-specific test suite with comprehensive coverage of WiFi
  operations.
- Added OS abstraction layer in `lib/wifi-wand/os/` for clean separation of
  OS-specific logic.

### User-Facing Commands and Features

- Added `-V` / `--version` to print the version and exit.
- Added `log` to monitor WiFi and Internet connectivity events.
- Added `qr` to generate a QR code for the current or specified WiFi network.
- Added `shell` as the interactive REPL entry point.
- Added sort-order control (`-o` / `--sort-order`) for available network lists.
- Added a `status` / `s` command for a one-line network status summary with DNS
  and TCP indicators.

### macOS Helper Application

- Replaced Swift/CoreWLAN scripts with a signed, notarized macOS helper
  application (`wifiwand-helper`).
- The helper is a Universal binary (ARM + Intel) and requires macOS 14.0 or
  later for location-based network scanning.
- Added `wifi-wand-macos-setup` to guide users through granting the necessary
  permissions.
- Added post-install guidance directing macOS users to the setup documentation.

### Connectivity and Network Reporting

- Added explicit connectivity states and richer CLI output.
- Added application-layer captive-portal detection after TCP probes.
- Added `captive_portal_free` to the `wifi_info` hash.
- Internet connectivity checks now use fast multi-endpoint TCP probes.
- IPv6 nameservers are now supported.
- `public_ip_address_info` now uses Ruby's `Net::HTTP` instead of `curl`.

### Architecture Improvements

- Large classes and files were broken into smaller, more cohesive components
  such as `HelpSystem`, `OutputFormatter`, and `ErrorHandling`.
- The system automatically detects the OS and loads the appropriate model.
- Extracted hardcoded data into YAML configuration files.
- Added `WifiWand::Client` as a cleaner programmatic API for library use.
- All OS commands are now executed using `Open3` with argument arrays,
  eliminating shell interpolation and command injection vulnerabilities.
- Switched from threads to the `async` gem for concurrent network detection.
- Extracted captive-portal detection into `CaptivePortalChecker`.
- Improved separation between OS detection, model creation, and command
  execution.
- Added proper error handling for unsupported operating systems.
- Enhanced the factory pattern for creating OS-specific models.
- Maintained backward compatibility where possible while adding new platform
  support.

### Error Handling Improvements

- Added comprehensive error classes and improved error messaging.
- Stack traces are no longer displayed unless in verbose mode.
- Added `WifiOffError` for operations that require WiFi to be on.
- Suppressed Pry stack traces for a cleaner interactive shell experience.

### Test Suite and Coverage Improvements

- Massive increase in test coverage.
- Added test coverage configuration.
- Created OS-agnostic common interface tests that work across supported
  platforms.
- Tests are divided into disruptive and nondisruptive categories.
- By default, only nondisruptive tests are run.
- Added support for disruptive-test inclusion and exclusion controls.
- Tests save state at suite start and restore state after disruptive tests.
- OS-specific tests are tagged and filtered when not on the native OS.
- Reduced the number of tests that do real OS calls.
- Simplified disruptive-test tag patterns.
- Added disruptive-test preflight enforcement.
- Hardened disruptive-test state capture so setup errors fail loudly.
- Added regression specs for OS tag filtering and disruptive-test skip logic.
- Added captive-portal specs for success, redirect, and all-network-error
  scenarios.
- Added branch coverage support with `COVERAGE_BRANCH=true`.
- Implemented coverage grouping by component.
- Created `CoverageConfig` in `spec/support/coverage_config.rb`.
- Made verbose mode accessible to tests via `WIFIWAND_VERBOSE`.
- Added helper methods for consistent test model creation.

### Documentation and Developer Workflow

- Completely rewrote `README.md` with improved structure and updated examples.
- Added detailed shell usage examples and variable-shadowing explanations.
- Updated installation instructions and troubleshooting sections.
- Expanded examples for both CLI and library usage.
- Added contact information and updated the cross-platform project
  description.
- Added `docs/TESTING.md`.
- Added a comprehensive `docs/` directory with user and developer indexes.
- Added a pre-commit hook that automatically runs safe tests before commits.
- Added `bin/setup-hooks` for hook installation.
- Hooks are stored in tracked `hooks/` and copied into `.git/hooks/`.
- Added `bin/op-wrap` to simplify 1Password-based development workflows.

### Additional Technical Changes

- Fixed the missing explicit `require 'stringio'` for modern Ruby versions.
- Added shell escaping for strings included in OS commands.
- Fixed `cycle_network` when WiFi starts in the off state.
- Improved verbose debug output.
- Updated gemspec dependencies and added version constraints.
- Updated the Ruby version constraint to `>= 3.2`.
- Added `rubygems_mfa_required` metadata.
- Converted simple one-line methods to Ruby 3 endless method syntax.
- Performed a broad RuboCop compliance pass across the codebase.
- Replaced `eval` with `JSON.parse` in output-format specs.
- Enhanced connection status monitoring with configurable timeouts.
- Removed real OS commands from nondisruptive unit tests.
- Changed the project license from MIT to Apache License 2.0.
