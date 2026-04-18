# macOS Helper Application for wifi-wand

> Audience: wifi-wand end users who need to install or troubleshoot the macOS helper.

This document explains the native macOS helper application that wifi-wand uses to access WiFi information on
macOS 14 (Sonoma) and later.

---

## Table of Contents

- [What is the Helper?](#what-is-the-helper)
- [Why Does wifi-wand Need a Helper?](#why-does-wifi-wand-need-a-helper)
- [Location Services Permissions](#location-services-permissions)
- [Managing the Helper](#managing-the-helper)
- [Troubleshooting](#troubleshooting)
- [Privacy and Security](#privacy-and-security)
- [Technical Details](#technical-details)

---

## What is the Helper?

The `wifiwand-helper` is a small native macOS application written in Swift that wifi-wand uses to retrieve
WiFi network information (SSID, BSSID, signal strength, etc.) on modern versions of macOS.

**Location:**
```
~/Library/Application Support/WifiWand/{version}/wifiwand-helper.app
```

**What it does:**
- Accesses WiFi interface information via Apple's CoreWLAN framework
- Requests Location Services authorization when needed
- Returns unredacted network names and details
- Operates as a separate process managed by macOS security

**When it's used:**
- Automatically on macOS 14.0 (Sonoma) and later
- When WiFi information would otherwise be redacted
- Only when you run wifi-wand commands that need network details

---

## Why Does wifi-wand Need a Helper?

### The macOS Security Changes

Starting with **macOS Sonoma (14.0)** (and continuing in Sequoia 15.x), Apple requires additional
authorization before command-line tools can see WiFi metadata:

#### Before macOS 14:
```bash
$ networksetup -getairportnetwork en0
Current Wi-Fi Network: MyNetwork
```

#### On macOS 14+ (before granting Location Services permission):
```bash
$ networksetup -getairportnetwork en0
Current Wi-Fi Network: <redacted>
```
Once the calling process (for example, Terminal.app) is approved for Location Services, those tools return the
full SSID again—but approval is scoped per executable. Your shell might work while `/usr/bin/ruby` (or a CI
runner) is still blocked, which is why the helper remains necessary.

### What Changed?

1. **SSID Redaction by Default**: Command-line tools like `networksetup` and `system_profiler` return
   `<redacted>` or blank values until the calling process is granted Location Services access.

2. **Location Services Requirement**: To access unredacted WiFi information, apps must:
   - Use Apple's CoreWLAN framework (not available from Ruby)
   - Request Location Services authorization
   - Be properly code-signed and registered with macOS

3. **Ruby Can't Do This Directly**: The wifi-wand gem (written in Ruby) cannot:
   - Access CoreWLAN framework
   - Request Location Services authorization
   - Create proper TCC (Transparency, Consent, and Control) entries

### The Solution

A native Swift helper application that:
- ✅ Uses CoreWLAN to access WiFi interfaces
- ✅ Requests Location Services authorization properly
- ✅ Is code-signed and notarized by the gem maintainer
- ✅ Returns unredacted network information to wifi-wand
- ✅ Operates transparently - you don't need to manage it

---

## Location Services Permissions

> When installing the gem on macOS, wifi-wand prints a reminder pointing back to this document so you know how
> to grant Location Services access after the helper runs the first time.

### Why Location Services?

Apple requires Location Services authorization to access WiFi SSIDs because:
- WiFi network names can reveal your physical location
- Known networks can be used to triangulate position
- This is a privacy protection measure

### What wifi-wand Can See

With Location Services authorization, the helper can access:
- Current WiFi network name (SSID)
- Network hardware address (BSSID)
- Signal strength (RSSI)
- Available nearby networks
- Security type (WPA2, WPA3, etc.)

### What wifi-wand Cannot See

The helper has **no access** to:
- ❌ Your actual GPS location
- ❌ Other apps' location data
- ❌ WiFi passwords
- ❌ Network traffic
- ❌ Connected devices

**The helper only requests permission to see WiFi network names, not to track your location.**

### When Does macOS Prompt?

- The first wifi-wand command that needs WiFi details launches `wifiwand-helper`, and macOS immediately asks
  for Location Services access.
- The dialog can appear behind other windows; if the command seems stuck, look for the prompt or
  open **System Settings → Privacy & Security → Location Services** to grant access manually once
  the helper appears there.
- macOS does **not** list `wifiwand-helper` in Location Services until the helper has run at least once. To
  register the helper with macOS and walk through permission granting in one step, run:
  ```bash
  wifi-wand-macos-setup
  ```

---

## Managing the Helper

wifi-wand ships a setup script for installing the helper and managing location permission.

### Update the Helper

If you want to force wifi-wand to replace the installed helper with the currently shipped one, run:

```bash
wifi-wand-macos-setup --repair
```

Use this after:
- Upgrading wifi-wand when you want to refresh the helper immediately
- Seeing helper crashes or startup failures
- Seeing `<hidden>` or `<redacted>` unexpectedly after the helper previously worked

If you have already installed a wifi-wand build that includes newer helper files, `--repair` is the fastest
way to put that updated helper on disk right now.

### Check Status and Install

```bash
wifi-wand-macos-setup
```

This command:
1. Checks whether the helper is installed and structurally valid
2. Checks whether Location Services permission is already granted
3. Exits immediately if everything is already set up:
   ```
   ✅ WifiWand macOS setup is complete! All requirements are satisfied.
   ```
4. Otherwise installs the helper (if needed) and opens System Settings so you can grant permission

### Repair or Reinstall

```bash
wifi-wand-macos-setup --repair
```

Use this when the helper is already installed but wifi-wand still shows `<hidden>` or `<redacted>` for network
names. It force-replaces the helper bundle and re-runs the authorization flow.

This is also the correct command when you want to update the installed helper immediately without waiting for
the next helper-backed wifi-wand command to notice that the bundle on disk is out of date.

### Revoke Location Permission

To remove wifi-wand's access to WiFi names:

1. Open **System Settings**
2. Go to **Privacy & Security → Location Services**
3. Find **wifiwand-helper** in the list
4. Toggle the switch to off

After revoking, wifi-wand falls back to system commands. On macOS 14+, SSID names may still be unavailable or
appear as `<redacted>`, but wifi-wand should continue to report the interface as connected when lower-level
association evidence is still present.

### Disable the Helper Entirely

If you prefer not to use the helper (accepting redacted WiFi names), set this environment variable before
running wifi-wand:

```bash
export WIFIWAND_DISABLE_MAC_HELPER=1
```

### Manual Permission Management

You can also manage permissions directly via System Settings:

1. Open **System Settings**
2. Go to **Privacy & Security → Location Services**
3. Scroll to find **wifiwand-helper** (the helper only appears here after it has run at least once — run any
   wifi-wand command or `wifi-wand-macos-setup` to seed the entry)
4. Toggle permission on or off

---

## Troubleshooting

### Helper Returns Empty Network Names

**Symptom:** wifi-wand shows blank or "none" for network names

**Possible Causes:**
1. Location Services permission not granted
2. Location Services disabled system-wide
3. Not connected to WiFi

**Solution:**
```bash
# Check status and grant permission if needed
wifi-wand-macos-setup

# Open Location Services directly if needed
open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
```

---

### Permission Prompt Doesn't Appear / Still Seeing `<hidden>`

**Symptom:** Ran `wifi-wand-macos-setup` but no prompt appeared, or network names are still redacted

**Possible Causes:**
1. Permission already granted or denied (check System Settings)
2. Helper bundle is stale, outdated, or macOS TCC has lost track of it
3. macOS cached the previous permission decision

**Solution:**
```bash
# Force-reinstall the helper and re-run the permission flow
wifi-wand-macos-setup --repair
```

If the prompt still does not appear after repair, open System Settings manually and look for
**wifiwand-helper** under Location Services. If it is present, toggle it off and back on.

---

### "Helper Installation Failed"

**Symptom:** Error message about helper installation failure

**Possible Causes:**
1. Corrupted helper files
2. File permission issues

**Solution:**
```bash
# Repair the helper installation
wifi-wand-macos-setup --repair

# If repair fails, remove the helper directory and run setup again
rm -rf ~/Library/Application\ Support/WifiWand/
wifi-wand-macos-setup
```

---

### Helper Works Without Permission?

**Observation:** On some macOS versions (notably 15.6.1), the helper successfully returns WiFi information
without creating a persistent TCC entry.

**Why this happens:**
This appears to be a quirk of macOS 15.x behavior where:
- The helper receives temporary authorization per-execution
- Authorization is not stored persistently in the TCC database
- WiFi information is still successfully retrieved

**Is this a problem?**
Not really — it means wifi-wand works without requiring explicit permission management on those versions.

---

## Privacy and Security

### Code Signing and Notarization

The helper application included in wifi-wand is:
- ✅ **Code-signed** with the gem maintainer's Apple Developer ID
- ✅ **Notarized** by Apple (passed security screening)
- ✅ **Open source** (Swift code available in the repository)
- ✅ **Minimal permissions** (only Location Services for WiFi)

### What Data is Collected?

The helper:
- ✅ Runs only when you invoke wifi-wand commands
- ✅ Returns data only to the wifi-wand process that launched it
- ✅ Does not send data to any external servers
- ✅ Does not store data on disk
- ✅ Does not run in the background
- ✅ Does not access your location coordinates

**You are in full control.** The helper only runs when you use wifi-wand, and you can revoke permissions at
any time via System Settings.

### Auditing the Helper

The helper's source code is available in the wifi-wand repository:
```
libexec/macos/src/wifiwand-helper.swift
libexec/macos/wifiwand-helper.app/Contents/Info.plist
libexec/macos/wifiwand-helper.entitlements
```

You can:
- Review the Swift source code
- Verify what permissions are requested
- Recompile from source if desired
- Report security concerns via GitHub issues

---

## Technical Details

### Helper Installation

The helper is automatically installed when you first run a wifi-wand command on macOS 14+:

1. wifi-wand detects macOS version ≥ 14.0
2. Checks whether the installed helper exists and matches the helper currently shipped with the gem
3. If it is missing or out of date, copies the current pre-signed helper from the gem installation
4. Helper is ready to use

### Helper Communication

```
┌─────────────┐
│  wifi-wand  │  (Ruby gem)
└──────┬──────┘
       │ launches
       ▼
┌─────────────────────┐
│ wifiwand-helper.app │  (Swift app)
└──────┬──────────────┘
       │ uses
       ▼
┌──────────────┐
│   CoreWLAN   │  (Apple framework)
└──────────────┘
       │
       ▼
   WiFi Interface
```

### Helper Output Format

The helper returns JSON:
```json
{
  "status": "ok",
  "interface": "en0",
  "ssid": "MyNetwork",
  "bssid": "aa:bb:cc:dd:ee:ff"
}
```

On error:
```json
{
  "status": "error",
  "error": "location services denied"
}
```

### Version Management

Each wifi-wand version installs its helper to a versioned directory:
```
~/Library/Application Support/WifiWand/
├── 3.0.0/
│   └── wifiwand-helper.app
├── 3.0.1/
│   └── wifiwand-helper.app
└── 3.1.0/
    └── wifiwand-helper.app
```

Old versions are not automatically removed (in case you have multiple wifi-wand versions installed). You can
safely delete old version directories.

Within the same gem version, wifi-wand also tracks whether the installed helper bundle still matches the
currently shipped helper files. If the helper bundle on disk is stale, wifi-wand reinstalls it automatically
before using it. You can force that refresh yourself at any time with `wifi-wand-macos-setup --repair`.

### Permission Identity and Version Upgrades

macOS identifies the helper by its **bundle identifier** (`com.wifiwand.helper`), not by its installed path.
This means:

- **Same gem version**: After granting Location Services permission once, subsequent uses don't require
  re-authorization.
- **New gem version**: Permission should continue automatically because the helper keeps the same bundle
  identifier and signing identity. Upgrading to a new wifi-wand version normally does not require another
  permission grant.

> **Note:** macOS TCC (Transparency, Consent, and Control) behavior can sometimes be sensitive to path,
> signature, or OS-version quirks. If macOS prompts for permission again after a gem upgrade, run
> `wifi-wand-macos-setup --repair` to force re-registration.

Multiple installed helper copies may exist on disk (one per gem version), but they present as one logical
macOS app identity for permission purposes via the stable bundle identifier `com.wifiwand.helper`.

### Disabling the Helper

If you prefer not to use the helper (accepting that WiFi names will be redacted), set:
```bash
export WIFIWAND_DISABLE_MAC_HELPER=1
```

wifi-wand will fall back to traditional methods. On macOS 14+, SSID names may still be unavailable or appear
as `<redacted>` unless the invoking process already has Location Services approval, but wifi-wand should still
detect an active WiFi association when the interface remains connected.

---

## For Gem Maintainers

If you're interested in the code signing and notarization process used to build the helper, see the maintainer
documentation in the repository:
- [docs/dev/MACOS_CODE_SIGNING.md](dev/MACOS_CODE_SIGNING.md)
  (not included in gem distribution)

---

## Additional Resources

- [wifi-wand Repository](https://github.com/keithrbennett/wifiwand)
- [Report Issues](https://github.com/keithrbennett/wifiwand/issues)
- [Apple Developer: Protecting User
  Privacy](https://developer.apple.com/documentation/corelocation/protecting_user_privacy)
- [Apple Support: Location
  Services](https://support.apple.com/guide/mac-help/change-location-services-settings-mh35873/mac)

---

**Last Updated:** 2026-04-18
**macOS Compatibility:** macOS 14.0 (Sonoma) and later
**Helper Version:** Matches wifi-wand gem version
