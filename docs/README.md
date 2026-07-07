# WifiWand Documentation Index

This directory contains end-user and operator documentation for `WifiWand` (gem name: `wifi-wand`).

## Getting Started

- **[Installation & Quick Start](../README.md)** - Basic setup and common command overview.
- **[macOS Quick Start](MACOS_QUICK_START.md)** - Crucial one-time setup steps for macOS users
  (Sonoma and later).
- **[Ubuntu Setup & Requirements](UBUNTU_SETUP.md)** - Requirements and configuration for Ubuntu systems.
- **[Security Notes](SECURITY_NOTES.md)** - Local WiFi password exposure surfaces and precautions.

## Command-Specific Guides

- **[Event Logging (`log`)](LOGGING.md)** - Monitor WiFi state changes and detect connectivity issues in
  real-time.
- **[Status Command (`s`)](STATUS_COMMAND.md)** - Detailed explanation of the connectivity status display and
  checks.
- **[Info Command (`i`)](INFO_COMMAND.md)** - Reference for the detailed network configuration output.
- **[Connectivity Checking (`ci`)](CONNECTIVITY_CHECKING.md)** - How to use `WifiWand` for automated internet
  health checks.
- **[DNS Configuration (`na`)](DNS_Configuration_Guide.md)** - Managing nameservers and custom DNS settings.

## Other Commands

Use `wifiwand --help` as the canonical command reference. Commands without dedicated guide pages include:

- `connect` / `co` - Join a WiFi network by SSID, optionally with a password.
- `disconnect` / `d` - Disassociate from the current WiFi network without powering WiFi off.
- `forget` / `f` - Remove saved preferred networks.
- `till` / `t` - Wait for WiFi power, association, or internet reachability states.
- `cycle` / `cy` - Toggle WiFi off and back on, or on and back off, depending on the starting state.
- `qr` - Generate Wi-Fi QR codes for terminal or file output.
- `public_ip` / `pi` - Query public IP address and country information.
- `ropen` / `ro` - Open useful network troubleshooting web resources.
- `random_mac` / `rmac` - Generate a random locally administered unicast MAC address.

## Technical Reference

- **[macOS Helper App Details](MACOS_HELPER_APP_DETAILS.md)** - End-user guidance for the native helper used
  on macOS 14+.

## Advanced Usage & Troubleshooting

- **[Environment Variables](ENVIRONMENT_VARIABLES.md)** - Configuring `WifiWand` via the environment
  (including `WIFIWAND_OPTS`).

## Project History

- **[Version 3 Breaking Changes](BREAKING_CHANGES_V3.md)** - Canonical upgrade and migration guide for
  version 3 API, CLI, and behavior changes.
- **[Release Notes](../RELEASE_NOTES.md)** - Release notes for all versions, including current unreleased changes.
- **[Version 3.0 Changes](CHANGELOG_V2_TO_V3.md)** - Broader summary of major improvements and non-breaking
  changes in version 3.0.

---

### For Developers and Maintainers

If you are contributing to `WifiWand` or working on the native helper, please see the **[Developer
Documentation Index](../dev/docs/README.md)**.
