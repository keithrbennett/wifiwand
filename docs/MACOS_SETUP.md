# macOS Location Permission Setup

## Why is this needed?

Starting with macOS 10.15 Catalina, Apple requires location permission for apps using the CoreWLAN framework
to access WiFi network names (SSIDs). wifi-wand uses a native helper with CoreWLAN for fast WiFi scanning.
Without location permission, the helper returns `<hidden>` for network names.
wifi-wand can still detect that WiFi is associated, but commands that must verify
the exact SSID such as `connect` and test-state restoration may report that the
network identity could not be verified until permission is granted.

On macOS 15 and earlier, wifi-wand can fall back to slower system commands. On newer macOS versions, CoreWLAN
with location permission may be the only way to access network names.

Granting location permission ensures wifi-wand works reliably across all macOS versions.

## One-Time Setup

Run the setup script after installing the gem:

```bash
wifi-wand-macos-setup
```

The script will:

1. **Check current status** - Verify if the helper is installed and has permission
2. **Install the helper** (if needed) - Copy the helper app to your Library folder
3. **Guide you through permission** (if needed) - Open System Settings where you can enable location access

### If Permission is Already Granted

If you've previously granted permission, the script will detect this and exit immediately:

```
✅ WifiWand macOS setup is complete! All requirements are satisfied.
```

### If Permission is Needed

The script will open System Settings → Privacy & Security → Location Services. Follow these steps:

1. Scroll down to find **wifiwand-helper** in the app list
2. Check the box next to **wifiwand-helper** to enable location access
3. Close System Settings

That's it! wifi-wand can now access WiFi network names.

## Verifying It Works

After setup, test with any wifi-wand command:

```bash
wifi-wand a              # Show available networks
wifi-wand info           # Show current connection info
```

You should see real network names instead of `<hidden>`.

## Running WifiWand on macOS With Redacted Network Names

If you choose not to grant Location Services permission, or if macOS is still
redacting WiFi identity after setup, wifi-wand can still perform some tasks.
However, several features become less reliable because the OS is hiding the
current SSID rather than because wifi-wand is missing logic.

### What Still Works

- wifi-wand can often still tell whether WiFi is on or off.
- wifi-wand can often still tell whether the interface is associated with some
  WiFi network.
- Commands that do not need the exact current SSID may still work normally.

### What Becomes Limited or Ambiguous

- `available_network_names` and related CLI output may show `<hidden>`,
  `<redacted>`, blank values, or no visible network names at all.
- `network_name`, `connected_network_name`, and other exact-SSID queries may
  fail even when the radio is associated, because wifi-wand cannot honestly
  verify the current SSID.
- `connect <ssid>` may successfully associate the interface but still fail with
  an error saying wifi-wand could not verify that the active network is the
  requested SSID.
- QR generation for the currently connected network may refuse to proceed,
  because it depends on knowing the exact current SSID.
- Test-state restoration and other restore flows may reconnect WiFi but still
  report that wifi-wand could not verify restoration of the original network.
- Requested real-environment test runs on macOS are refused before the suite
  starts when the current SSID is redacted or otherwise unverifiable. The suite
  contract requires capturing the original SSID and proving restoration to that
  exact SSID afterward, not merely proving association to some network.
- Any workflow that depends on proving "this is the exact SSID" is subject to
  OS-level uncertainty until Location Services permission is granted.

### What WifiWand Will Not Do

wifi-wand does not silently downgrade exact-network verification to "some
network is good enough" when macOS redacts identity. If a command's contract
requires confirming the requested or original SSID, wifi-wand reports that the
verification could not be completed instead of pretending success.

This is intentional. When macOS hides the only trustworthy network identity,
wifi-wand cannot reliably distinguish the intended network from a different
remembered network that auto-reassociated on its own.

### Recommendation

If you want reliable `connect`, restore, scan, and current-network behavior on
modern macOS, run:

```bash
wifi-wand-macos-setup
```

Then grant Location Services access to `wifiwand-helper`.

## Troubleshooting

**Q: I don't see wifiwand-helper in Location Services**

Run the setup script again. It will register the helper with macOS.

**Q: I granted permission but still see `<hidden>`**

Try running wifi-wand again. If the issue persists, the helper may need to be reinstalled. Run the
repair flag, which replaces the helper bundle and prompts you to re-grant permission:

```bash
wifi-wand-macos-setup --repair
```

**Q: Does wifi-wand track my location?**

No. Location permission is only used to access WiFi network names. wifi-wand does not access your physical
location, GPS coordinates, or any location data. This is an Apple requirement for accessing WiFi information,
not something wifi-wand uses.
