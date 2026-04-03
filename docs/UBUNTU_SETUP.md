# Ubuntu Setup and Requirements

## Overview

Unlike macOS (which requires location permission for WiFi scanning), `wifi-wand` on Ubuntu and Ubuntu-based distributions (Linux Mint, Pop!_OS, elementary OS, etc.) works out-of-the-box on most standard installations. It relies on the industry-standard **NetworkManager** suite.

## Requirements

`wifi-wand` requires **Ruby >= 3.2.0** and the following core Ubuntu tools:

- **NetworkManager** (`nmcli`): Required for managing connections, status, WiFi radio state, and DNS settings.
- **iw**: Required for WiFi interface detection and wireless capability checks.

The following tools are used for specific features but are not required for every command:

- **iproute2** (`ip`): Used for IP address, MAC address, and routing information.
- **qrencode** (Optional): Required only for the `qr` command to generate Wi-Fi QR codes.
- **xdg-open** (Optional): Required only for the `ropen` command to open URLs in a browser. Pre-installed on most desktop environments.

On many Ubuntu Desktop installations, `nmcli`, `iw`, and `ip` are already present, but that is environment-dependent.

### Installing Dependencies

If any commands are missing, you can install them via `apt`:

```bash
sudo apt update
sudo apt install network-manager iw iproute2 qrencode xdg-utils
```

## User Permissions

For most commands, `wifi-wand` uses the current user's permissions via `nmcli`.

- **Standard usage**: Read-only commands usually work without additional privileges.
- **Network changes**: Connecting, disconnecting, toggling WiFi, or changing DNS settings may require authorization depending on your NetworkManager and PolKit configuration.
- **Desktop sessions**: On a typical Ubuntu Desktop system, an interactive logged-in user can often perform these actions without `sudo`.
- **Restricted environments**: On servers, minimal installs, containers, or custom policy setups, some commands may fail until permissions are adjusted or the command is run with sufficient privileges.

## NetworkManager Profiles vs. SSIDs

One important distinction on Ubuntu is that `nmcli` operates on **connection profiles**.

When you connect to a network named "MyWiFi", NetworkManager creates a profile (often also named "MyWiFi"). If you connect to multiple networks with the same name or change settings, you might end up with profiles named "MyWiFi 1", etc.

`wifi-wand` handles this by:
1. Scanning for available SSIDs.
2. Matching SSIDs to the most recently used connection profile.
3. Automatically creating or updating profiles as needed during connection.

## Troubleshooting

### NetworkManager is not running

If you see errors related to `nmcli`, ensure the NetworkManager service is active:

```bash
systemctl status NetworkManager
```

If it's stopped, start it with:

```bash
sudo systemctl start NetworkManager
```

To ensure it starts automatically on boot:

```bash
sudo systemctl enable --now NetworkManager
```

### No WiFi Interface Found

If `wifi-wand` cannot find your WiFi interface:
1. Verify the hardware is detected: `iw dev`
2. Ensure the radio is on: `nmcli radio wifi`
3. If using a custom interface, specify it with `-p`: `wifi-wand -p wlan0 status`

### QR Code Generation Fails

If the `qr` command fails, ensure `qrencode` is installed:
```bash
sudo apt install qrencode
```

### No Visible Networks Found

If `wifi-wand` reports no visible networks but you expect to see some:
1. Trigger a manual scan: `nmcli device wifi rescan`
2. Ensure your WiFi radio is on: `nmcli radio wifi`
3. Check that your hardware and drivers are working: `iw dev`
