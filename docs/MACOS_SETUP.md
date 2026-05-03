# macOS Location Permission Setup

## Recommendation

If you want reliable `connect`, restore, scan, and current-network behavior on
macOS 14 and later, run:

```bash
wifi-wand-macos-setup
```

Then grant Location Services access to the `wifiwand-helper` helper application.

## Why is this needed?

Starting with macOS 14 Sonoma, Apple redacts WiFi network names (SSIDs) from ordinary command-line tools
unless the calling app has Location Services permission. wifi-wand uses a native macOS helper application
with CoreWLAN for permission-sensitive reads such as current-network lookup and available-network scanning.
Without the helper application, or without Location Services permission for the helper application, macOS may
return `<hidden>`, `<redacted>`, blank values, or no usable SSID at all.

wifi-wand can still often detect that WiFi is associated, but commands that must verify the exact SSID, such
as `connect` and test-state restoration, may report that the network identity could not be verified until the
helper application is installed and permission is granted.

wifi-wand currently uses two Swift/CoreWLAN runtime paths on macOS:
- The compiled `wifiwand-helper.app` helper application path handles read/query operations on macOS 14 and
  later. This setup flow installs that helper application and grants Location Services permission for it.
- The direct Swift source scripts handle connect/disconnect mutations when Swift/CoreWLAN is available, with
  `networksetup`/`ifconfig` fallbacks. These mutations do not require the `wifiwand-helper.app` helper
  application, but connect can still be affected when macOS redacts the SSID needed for post-connect
  verification.

On macOS 13 and earlier, wifi-wand does not use the compiled helper application and generally relies on
system commands. On macOS 14 and later, the helper application plus Location Services permission is the
reliable path for exact network names.

Granting Location Services permission ensures wifi-wand works reliably on macOS versions that redact SSIDs.

## One-Time Setup

Run the setup script after installing the gem on macOS 14 or later:

```bash
wifi-wand-macos-setup
```

On macOS 13 and earlier, this setup is not needed. The helper application is
built for macOS 14 or later, and wifi-wand does not use the helper application
on older macOS versions. If you try to install it there, the setup flow may
fail helper application validation because macOS cannot run the helper
application.

The script will:

1. **Check current status** - Verify if the helper application is installed and has permission
2. **Install the helper application** (if needed) - Copy the helper application to your Library folder
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

That's it! The helper application can now return unredacted WiFi network names to wifi-wand.

## Verifying It Works

After setup, test with any wifi-wand command:

```bash
wifi-wand a              # Show available networks
wifi-wand info           # Show current connection info
```

You should see real network names instead of `<hidden>`.

## Running WifiWand on macOS Without the Helper Application or With Redacted Network Names

If you choose not to install or use the `wifiwand-helper.app` helper
application, if you set `WIFIWAND_DISABLE_MAC_HELPER=1`, if helper application
installation fails, or if macOS is still redacting WiFi identity after setup,
wifi-wand can still perform some tasks. However, several features become less
reliable because the OS is hiding the SSID rather than because wifi-wand is
missing logic.

### What Still Works

- wifi-wand can often still tell whether WiFi is on or off.
- wifi-wand can often still tell whether the interface is associated with some
  WiFi network.
- `wifi_on`, `wifi_off`, nameserver changes, interface lookup, IP/MAC queries,
  and internet connectivity checks may still work when their underlying system
  commands provide enough information.
- `disconnect` does not require the helper application. It uses the direct
  Swift source path when available and falls back to `ifconfig`.
- `connect <ssid>` does not require the helper application to attempt
  association. It uses the direct Swift source path when available and falls back to
  `networksetup`.
- Commands that do not need the exact current SSID may work normally.

### What Becomes Limited or Ambiguous

- `available_network_names` and related CLI output may fall back to
  `system_profiler`, but on macOS 14 and later that fallback may show
  `<hidden>`, `<redacted>`, blank values, or no visible network names at all
  unless the helper application can return unredacted names.
- `network_name`, `connected_network_name`, and other exact-SSID queries may
  return nil or fail even when the radio is associated, because wifi-wand cannot
  honestly verify the current SSID.
- `connect <ssid>` may successfully associate the interface but still fail
  afterward with an error saying wifi-wand could not verify that the active
  network is the requested SSID.
- QR generation for the currently connected network may refuse to proceed,
  because it depends on knowing the exact current SSID.
- Test-state restoration and other restore flows may reconnect WiFi but still
  report that wifi-wand could not verify restoration of the original network.
- Requested real-environment test runs on macOS are refused before the suite
  starts when the current SSID is redacted or otherwise unverifiable. The suite
  contract requires capturing the original SSID and proving restoration to that
  exact SSID afterward, not merely proving association to some network.
- Any workflow that depends on proving "this is the exact SSID" is subject to
  OS-level uncertainty until Location Services permission is granted to the
  helper application.

### What WifiWand Will Not Do

wifi-wand does not silently downgrade exact-network verification to "some
network is good enough" when macOS redacts identity. If a command's contract
requires confirming the requested or original SSID, wifi-wand reports that the
verification could not be completed instead of pretending success.

This is intentional. When macOS hides the only trustworthy network identity,
wifi-wand cannot reliably distinguish the intended network from a different
remembered network that auto-reassociated on its own.

## Troubleshooting

**Q: I don't see wifiwand-helper in Location Services**

Run the setup script again. It will register the helper application with macOS.

**Q: I granted permission but still see `<hidden>` or `<redacted>`**

Try running wifi-wand again. If the issue persists, the helper application may need to be reinstalled. Run
the repair flag, which replaces the helper application bundle and prompts you to re-grant permission:

```bash
wifi-wand-macos-setup --repair
```

**Q: Does wifi-wand track my location?**

No. Location permission is only used to access WiFi network names. wifi-wand does not access your physical
location, GPS coordinates, or any location data. This is an Apple requirement for accessing WiFi information,
not something wifi-wand uses.
