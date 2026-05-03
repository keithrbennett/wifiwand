# macOS Location Permission Setup

Use this guide for the one-time setup required on macOS 14 Sonoma and later. For the detailed explanation of
the native helper application, privacy model, repair behavior, and technical details, see
[MACOS_HELPER_APP_DETAILS.md](MACOS_HELPER_APP_DETAILS.md).

## Recommendation

After installing the gem on macOS 14 or later, run:

```bash
wifi-wand-macos-setup
```

Then grant Location Services access to the `wifiwand-helper` helper application when System Settings opens.

This setup gives wifi-wand a stable macOS app identity for permission-sensitive WiFi reads such as current
network lookup and nearby network scans. Without it, macOS may return `<hidden>`, `<redacted>`, blank values,
or no usable SSID.

On macOS 13 and earlier, this setup is not needed. The compiled helper application is built for macOS 14 or
later, and wifi-wand does not use it on older macOS versions.

## Setup Steps

1. Run the setup command:

   ```bash
   wifi-wand-macos-setup
   ```

2. If System Settings opens, go to **Privacy & Security > Location Services**.
3. Find **wifiwand-helper** in the app list.
4. Enable Location Services access for **wifiwand-helper**.
5. Close System Settings.

If permission is already granted, the command exits immediately:

```text
WifiWand macOS setup is complete! All requirements are satisfied.
```

## Verify Setup

Run a command that needs WiFi network names:

```bash
wifi-wand a
wifi-wand info
```

You should see real network names instead of `<hidden>` or `<redacted>`.

## Repair Setup

If setup completed but network names are still hidden or redacted, see
[MACOS_HELPER_APP_DETAILS.md](MACOS_HELPER_APP_DETAILS.md) for repair and troubleshooting steps.

## Running With Redacted Network Names

See [MACOS_HELPER_APP_DETAILS.md](MACOS_HELPER_APP_DETAILS.md) for the full behavior matrix,
troubleshooting details, privacy notes, and instructions for disabling the helper application.
