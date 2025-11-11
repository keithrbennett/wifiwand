# macOS Location Permission Setup

## Why is this needed?

Starting with macOS 10.15 Catalina, Apple requires location permission for apps using the CoreWLAN framework to access WiFi network names (SSIDs). wifi-wand uses a native helper with CoreWLAN for fast WiFi scanning. Without location permission, the helper returns `<hidden>` for network names.

On macOS 15 and earlier, wifi-wand can fall back to slower system commands. On newer macOS versions, CoreWLAN with location permission may be the only way to access network names.

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

## Troubleshooting

**Q: I don't see wifiwand-helper in Location Services**

Run the setup script again. It will register the helper with macOS.

**Q: I granted permission but still see `<hidden>`**

Try running wifi-wand again. If the issue persists, the helper may need to be reinstalled:

```bash
bundle exec rake mac:rm_helper
wifi-wand-macos-setup
```

**Q: Does wifi-wand track my location?**

No. Location permission is only used to access WiFi network names. wifi-wand does not access your physical location, GPS coordinates, or any location data. This is an Apple requirement for accessing WiFi information, not something wifi-wand uses.
