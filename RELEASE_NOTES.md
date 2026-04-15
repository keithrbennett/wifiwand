## Unreleased

### Breaking Changes

#### `connected_to_internet?` replaced by `internet_connectivity_state`

The old boolean-style `connected_to_internet?` API has been **removed** and
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

**Migration guidance:**

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

#### Breaking: Public IP info removed from `info`

This is a breaking change in both location and data shape.

The `info` command no longer returns `public_ip`. The entire
`info["public_ip"]` container has been removed. Public IP lookup is now an
explicit CLI feature exposed through `public_ip` and its short alias `pi`.

**What changed:**

| Old | New |
|-----|-----|
| `info["public_ip"]` | `wifi-wand public_ip` / `wifi-wand pi` |
| nested `public_ip` object inside `info` | dedicated command result |
| broader unauthenticated IPinfo payload | narrower result with only `address` and `country` |

**Fields no longer provided:**

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

**Migration guidance:**

- old: `info["public_ip"]`
- new, both fields: `wifi-wand public_ip` or `wifi-wand pi`
- new, address only: `wifi-wand public_ip address` or `wifi-wand pi a`
- new, country only: `wifi-wand public_ip country` or `wifi-wand pi c`

**Current result shape:**

```json
{
  "address": "203.0.113.5",
  "country": "TH"
}
```

This change keeps `info` focused on local network state and makes external
public-IP lookup explicit.

#### `till` wait-state vocabulary redesigned

The `till` command now uses an explicit, unambiguous vocabulary. The old state names
`conn`, `disc`, `on`, and `off` have been **removed**.

**Why?** `conn` checked full Internet reachability (`internet_connectivity_state == :reachable`),
not WiFi association. This caused semantic confusion: code that connected to a WiFi
network then called `till(:conn)` was really asking "is the Internet up?" rather than
"did I join the network?". The new vocabulary makes the distinction explicit.

**New state names:**

| State           | Meaning                                                         |
|-----------------|-----------------------------------------------------------------|
| `wifi_on`       | WiFi hardware is powered on                                     |
| `wifi_off`      | WiFi hardware is powered off                                    |
| `associated`    | WiFi is associated with an SSID (WiFi layer, not Internet)      |
| `disassociated` | WiFi is not associated with any SSID                            |
| `internet_on`   | Internet connectivity state is reachable                        |
| `internet_off`  | Internet connectivity state is unreachable                      |

`internet_connectivity_state` can also be `:indeterminate` when TCP and DNS
succeed but captive-portal checks cannot determine whether the Internet is
actually reachable. There is no dedicated `till` target for this state;
`internet_on` matches only `:reachable`, and `internet_off` matches only
`:unreachable`.

**Migration table:**

| Old usage         | New usage                                         |
|-------------------|---------------------------------------------------|
| `till on`         | `till wifi_on`                                    |
| `till off`        | `till wifi_off`                                   |
| `till conn`       | `till internet_on` or `till associated`           |
| `till disc`       | `till internet_off` or `till disassociated`       |

Using a removed name now raises an `ArgumentError` with a clear message listing the
valid state names.

**Internal changes:** connection flows now wait for WiFi association (`:associated`)
rather than Internet reachability; restore flows wait for WiFi power state
(`:wifi_on`/`:wifi_off`) as appropriate.

---

## v3.0.0.pre-alpha.1

### The Big Kahuna

* **Added first-class Ubuntu (and compatible Linux) support alongside macOS, exposing a single unified
  interface across platforms.**

### Breaking Changes
* `cycle_network` now toggles WiFi state twice regardless of starting state (on or off). Previously it
  unconditionally did off, then on.
* Removed macOS Speedtest application launch support; the web site is still available via the `ro spe`
  command.
* Removed `fancy_print`. Awesome Print is now a required gem so it is always available, so there is no need
  for fancy_print.
* We no longer assume that if WiFi is off there is no Internet connectivity, since that connectivity can be
  provided by an Ethernet connection
  * The 'ci' (connected to Internet) command can now return true if WiFi is off but there is another Internet
    connection.
* The `-s`/`--shell` command-line option has been replaced with a `shell` subcommand (e.g. `wifi-wand shell`
  instead of `wifi-wand -s`).
* All environment variables have been renamed to use the `WIFIWAND_` prefix (e.g. `WIFIWAND_VERBOSE`,
  `WIFIWAND_OPTS`).
* Removed the `l`/`ls_avail_nets` command; it is no longer operational.
* The `--hook` option for the `log` subcommand has been removed. The hook execution feature was incomplete and
  never properly tested; its removal simplifies the codebase and eliminates a security concern.

### New Commands & Features

* **`-V`/`--version`** — Print the version and exit.
* **`log` subcommand** — Monitor and log internet connectivity events
  (connect/disconnect) to stdout and/or a file. Detects outages using fast multi-endpoint TCP probes.
* **`qr` command** — Generate a QR code for the currently connected WiFi network (or a specified network),
  enabling easy sharing with mobile devices. Supports output to stdout or a file.
* **`shell` subcommand** — Launch an interactive REPL shell (replaces the `-s`/`--shell` option).
* **Sort order option** (`-o`/`--sort-order`) — Control the sort order (`a`/`ascending` or `d`/`descending`)
  of the available networks list.

### macOS: New Signed Helper Application

* Replaced Swift/CoreWLAN scripts with a signed, notarized macOS helper application (`wifiwand-helper`) that
  enables WifiWand to access WiFi network names without triggering repeated authorization prompts.
* The helper is a Universal binary (ARM + Intel) and requires macOS 14.0 or later for location-based network
  scanning.
* A `wifi-wand-macos-setup` script is provided to guide users through granting the necessary permissions.
* A post-install gem message directs macOS users to the setup documentation.

### User Experience Improvements

* Added support for `WIFIWAND_VERBOSE` environment variable to simulate `-v` flag. This is especially useful
  for testing.
* Added `WIFIWAND_OPTS` environment variable to prepend default command-line options before parsing user
  input.
* Added a `status`/`s` command for displaying a 1-line network status summary with DNS and TCP connectivity
  icons.
* Help output is now styled with a formatted banner.
* In non-interactive mode, the process now exits with code 1 if any errors occur (unless only help text was
  requested).
* Empty-string passwords are now treated as deliberate open-network connection attempts, skipping saved
  credential lookups.
* Improved validation for user-provided SSIDs and passwords.

### Architectural Improvements

* Large classes and files have been broken into smaller, more specific and
cohesive classes and files (HelpSystem, OutputFormatter, ErrorHandling, etc.).
* The system automatically detects the OS and loads the appropriate model for that OS.
* Extracted hardcoded data into YAML configuration files.
* **Client class** — A new `WifiWand::Client` class provides a clean programmatic API for use as a library.
* **Secure command execution** — All OS commands are now executed using `Open3` with argument arrays,
  eliminating shell interpolation and command injection vulnerabilities.
* Switched from threads to the `async` gem for concurrent network detection.
* **`CaptivePortalChecker` service class** — Captive-portal detection logic has been extracted from
  `NetworkConnectivityTester` into a dedicated class for better separation of concerns.

### Network Management & Reporting Improvements

* The 'connected to Internet?' functionality has been improved:
  * wifi off will no longer by itself cause it to return false, since there may be an Ethernet connection
  * DNS and TCP tests are both done, with separate indicators in the new 'status' command's output.
  * An HTTP application-layer check is now performed after the TCP probes to detect expired captive portal
    sessions. A `GET` to `http://connectivitycheck.gstatic.com/generate_204` must return `204 No Content`; a
    redirect or HTML response is treated as no connectivity. Plain HTTP is used deliberately so that
    TLS-intercepting portals cannot silently forward the check. If all HTTP check requests fail with network
    errors the method errs on the side of reporting connected (fail-open).
  * The `wifi_info` hash now includes a `captive_portal_free` boolean key alongside `connected_to_internet`,
    `dns_working`, and `tcp_working`.
* Internet connectivity checks now use fast multi-endpoint TCP probes (~50–200ms typical, 1s worst case)
  instead of slower DNS+TCP checks.
* IPv6 nameservers are now supported.
* `public_ip_address_info` now uses Ruby's `Net::HTTP` instead of `curl`, removing the external dependency.

### Error Handling Improvements
* Added comprehensive error classes and improved error messaging.
* Stack traces are no longer displayed unless in verbose mode.
* Added `WifiOffError`, a specific error class raised when an operation is attempted that requires WiFi to be
  on.

### Testing Improvements
* Massive increase in test coverage.
* Added test coverage configuration.
* Tests are divided into disruptive (system state changing) and nondisruptive tests.
* By default, only nondisruptive tests are run.
* Disruptive test inclusion and exclusion can be controlled with the `RSPEC_DISRUPTIVE_TESTS` environment
  variable.
* Tests save state at start of test suite and restore that state after each "disruptive" test and at the end
  of the test suite.
* OS-specific tests are tagged with their OS and excluded when not the native OS.
* The number of tests that do real OS calls has been greatly reduced, speeding testing and enabling the more
  frequent testing of some behavior.
* **Simplified disruptive-test tags.** The two-tag pattern `:disruptive, :os_mac` / `:disruptive, :os_ubuntu`
  has been replaced with single combined tags `:disruptive_mac` / `:disruptive_ubuntu`. A
  `define_derived_metadata` block back-fills `:disruptive` so all existing filtering, after-hooks, and
  network-state management continue to work unchanged.
* **Disruptive-test preflight enforcement.** The test suite now aborts immediately
  (rather than silently skipping) if the required preconditions for disruptive tests — WiFi on
  and connected to a network — are not met at suite start.
* **Disruptive-test state capture hardened.** Errors in state capture now propagate as failures instead of
  being silently rescued.
* Added regression specs for OS tag filtering and disruptive-test skip logic.
* New captive-portal specs covering `captive_portal_free?`: 204 pass, 302 fail, all-network-errors failsafe,
  and verbose output paths.

### Documentation Improvements

* README has been improved and updated to reflect the changes.
* A TESTING.md file has been added.
* A CLAUDE.md file generated and used by Claude Code has helpful information about the code base.
* Prompts located in a `prompts/` directory are used to create and update some documents using AI, such as "OS
  Command Use" for each supported OS.
* Comprehensive `docs/` directory with separate user and developer documentation indexes.

### Bug Fixes
* Fixed the lack of explicit require of 'stringio' for modern Ruby versions.
* Added shell escaping for strings included in OS commands.
* Fixed `cycle_network` to correctly handle the case where WiFi starts in the off state.

### Verbose Mode Debug Output

* Many improvements have been made.

### Technical Changes
* gemspec:
  * Updated some gemspec gem specifications for the first time in years.
  * Added version constraints where there were none.
  * Ruby version constraint updated to >= 3.2 (required by the `async` gem via `traces`).
  * Added `rubygems_mfa_required` metadata.
* **Ruby 3 endless method syntax** — All simple single-line methods (`def f; expr; end`) across `lib/` and
  `spec/` have been converted to the endless form (`def f = expr`).
* **Comprehensive RuboCop compliance pass** — Hundreds of Layout, Style, Lint, and Naming offenses corrected
  across the entire codebase.
* **Replaced `eval` with `JSON.parse`** in output-format specs (RuboCop `Security/Eval`).
* **Status monitoring** - Enhanced connection status monitoring with configurable timeouts
* **Mock testing** - Removed real OS commands from non-disruptive unit tests
* Added a `bin/op-wrap` script to simplify using 1Password for credential management during development.

This major release represents a complete rewrite focused on cross-platform support while maintaining backward
compatibility for existing macOS users.


## v2.20.0

* Change detect_wifi_interface and available_network_names to use system_profiler JSON output.
* Previously, detect_wifi_interface parsed human readable text; parsing JSON is more reliable.
* Previously, available_network_names used Swift and CoreLAN and required XCode installation.


## v2.19.1

* Fix connected_network_name when WiFi is on but no network is connected.


## v2.19.0

* Replace `networksetup` with Swift script for connecting to a network.
* For getting connected network name, replace `networksetup` with `ipconfig`. 


## v2.18.0

* Remove 'hotspot_login_required' informational item and logic (was not working correctly).


## v2.17.1

* Fix verbose output for running a Swift command. 
* Exit Swift programs with code 1 on error.
* Remove rexml dependency, no longer needed.


## v2.17.0

* Remove all remaining uses of the 'airport' command.
* Remove 'available_network_info' command which required the 'airport' command.
* Remove extended information in the 'info' command output, which required the 'airport' command.
* Remove unused ModelValidator class.
* In README, update license reference and make other edits.


## v2.16.1

* Fix airport deprecations' removal of listing all networks and disconnecting from a network by using Swift
  scripts.


## v2.16.0 (2024-04)

* Handle deprecation of the `airport` command starting at macOS 14.4.
* Add hotspot_login_required functionality.
* Change 'port' to 'interface' in some names.
* Add to external resources: captive.apple.com, librespeed.org
* Change license from MIT to Apache 2.


## v2.15.2

* Improve support for 'hotspot login required'.
* Add 'hotspot_login_required' field to info hash, & on connect, opens captive.aple.com page if needed.
* Change license from MIT to Apache 2.


## v2.15.1

* Fix bug; when calling connect with an SSID with leading spaces, a warning was erroneously issued about the
  SSID.


## v2.15.0

* Allow using symbols in the 'nameservers' subcommands.
* Modify `forget` method to allow passing a single array of names, as returned by `pr.grep`, for example.
* Output duration of http get's.


## v2.14.0

* `ls_avail_nets` command now outputs access points in signal strength order.
* Add logo to project, show it in README.md.

## v2.13.0

* Fix: network names could not be displayed when one contained a nonstandard character (e.g. D5 for a special
  apostrophe in Mac Roman encoding).
* Fix: some operations that didn't make sense with WiFi off were attempted anyway; this was removed.

## v2.12.0

* Change connected_to_internet?. Use 'dig' to test name resolution first, then HTTP get. Also, add baidu.com
  for China where google.com is blocked.
* Remove ping test from connected_to_internet?. It was failing on a network that had connectivity (Syma in
  France).
* Remove trailing newline from MAC address.
* Fix nameservers command to return empty array instead of ["There aren't any DNS Servers set on Wi-Fi."]
  (output of underlying command)when no nameservers.


## v2.11.0

* Various fixes and clarifications.
* Change implementation of available_network_names to use REXML; first implemented w/position number, then
  XPath.
* Add attempt count to try_os_command_until in verbose mode.

## v2.10.1

* Fix egregious bug; the 'a' command did not work if `airport` was not in the path; I should have been using
  the AIRPORT_CMD constant but hard coded `airport` instead.

## v2.10.0

* Rename rm[_pref_nets] command to f[orget].
 

## v2.9.0

* Add duration of command to verbose output.
* Add MAC address to info hash.
* Reduce ping timeout to 3 seconds for faster return for `info`, `ci` commands.
* Replace ipchicken.com link with iplocation.net link for 'ropen'; iplocation aggregates several info sources.
* Fix bug where if there were no duplicate network names, result was nil, because uniq! returns nil if no
  changes!!!
* Suppress error throw on ping error when not connected; it was printing useless output.

## v2.8.0

* Substantial simplifications of model implementations of connected_to_internet?, available_network_names.
* Fixed network name reporting problems regarding leading/trailing spaces.
* Improve verbose output by printing command when issued, not after completed.


## v2.7.0

* Fix models not being loadable after requiring the gem.
* Add message suggesting to gem install awesome_print to help text if not installed.
* Add Github project page URL to help text.
* Rename 'wifion' to 'wifi_on'.
* Change order of verbose output and error raising in run_os_commmand.


## v2.6.0

* Add support for getting and setting DNS nameservers with 'na'/'nameservers' command.
* Improve error output readability for top level error catching.


## v2.5.0

* Add limited support for nonstandard WiFi devices (https://github.com/keithrbennett/wifiwand/issues/6).


## v2.4.2

* Fix test.


## v2.4.1

* Fix bug: undefined local variable or method `connected_network_name'.


## v2.4.0

* Project has been renamed from 'mac-wifi' to 'wifi-wand'.
* Further preparation for addition of support of other OS's.
* Make resource opening OS-dependent as it should be.
* Move models to models directory.
* Refactored OS determination and model creation.
* Use scutil --dns to get nameserver info, using the union of the scoped and unscoped nameservers.


## v2.3.0

* Add public IP address info to info hash (https://github.com/keithrbennett/macwifi/issues/3).
* Add nameserver information to info hash (issue at https://github.com/keithrbennett/macwifi/issues/5).
* Made all info hash keys same data type to be less confusing; made them all String's.
* Replace 'public-ip-show' with 'ropen', and provide additional targets ipchicken.com,
 speedtest.net, and the Github page for this project
* Speed up retrieval of network name
* Remove BaseModel#run_os_command private restriction.


## v2.2.0

* Add pu[blic-wifi-show] command to open https://www.whatismyip.com/ to show public IP address info.
* Removed 'vpn on' info from info hash; it was often inaccurate.


## v2.1.0

* Support for the single script file install has been dropped. It was requiring too much complexity,
and was problematic with Ruby implementations lacking GEM_HOME / GEM_PATH environment variables.
* Code was broken out of the single script file into class files, plus a `version.rb`
and `mac-wifi.rb` file.


## v2.0.0

* Support output formats in batch mode: JSON, YAML, puts, and inspect modes.
* Change some command names to include underscores.
* Shell mode is now (only) a command line switch (-s).


## v1.4.0

* Support for "MAC-WIFI-OPTS" environment variable for configuration dropped.
* Support for "-v" verbosity command line option added.
* Work around pry bug whereby shell was not always starting when requested.
* 99% fix for reporting of available network names containing leading spaces
  (this will not correctly handle the case of network names that are identical
  except for numbers of leading spaces).
* Improved handling of attempting to list available networks when WiFi is off.


## v1.3.0

* Add partial JSON and YAML support.
* Script moved from bin to exe directory.
* Provide `fp` fancy print alias for convenience in shell.
* Command renames: 'lsp' -> 'prefnets', 'rm' -> 'rmprefnets'
* Add 'availnets' command for list of unique available network names.


## v1.2.0

* Fix: protect against using command strings shorter than minimum length
      (e.g. 'c', when more chars are necessary to disambiguate multiple commands).
* Improvements in help text and readme.


## v1.1.0

* Sort available networks alphabetically, left justify ssid's.
* to_s is called on parameters so that symbols can be specified in interactive shell for easier typing


## v1.0.0

* First versioned release.
