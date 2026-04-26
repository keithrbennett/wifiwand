# Version 2.x to 3.0 Code Base Changes

This document summarizes the major changes introduced in version 3.0 compared
to version 2.x.

Version 3.0 also includes some intentional API and implementation cleanup.
Part of the motivation for these changes was to trim accidental surface area,
remove features that were not pulling their weight, and keep the codebase
smaller and easier to reason about before broader release.

For upgrade-impacting API, CLI, and behavior changes, see
[Version 3 Breaking Changes](BREAKING_CHANGES_V3.md).

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
- Added a direct model API for library use, with OS detection separated from
  model behavior.
- All OS commands are now executed using `Open3` with argument arrays,
  eliminating shell interpolation and command injection vulnerabilities.
- Renamed the direct command execution APIs to `run_command_using_args` and
  `run_command_using_shell` so structured execution and shell execution are
  distinguished explicitly for library consumers.
- Added native-thread concurrency for status and connectivity reporting where
  overlapping OS and network checks improve latency.
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
- Added `dev/docs/TESTING.md`.
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
