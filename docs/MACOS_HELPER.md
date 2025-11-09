# macOS Helper Application for wifi-wand

> Audience: wifi-wand end users who need to install or troubleshoot the macOS helper.

This document explains the native macOS helper application that wifi-wand uses to access WiFi information on macOS 14 (Sonoma) and later.

---

## Table of Contents

- [What is the Helper?](#what-is-the-helper)
- [Why Does wifi-wand Need a Helper?](#why-does-wifi-wand-need-a-helper)
- [Location Services Permissions](#location-services-permissions)
- [Managing Permissions](#managing-permissions)
- [Troubleshooting](#troubleshooting)
- [Privacy and Security](#privacy-and-security)
- [Technical Details](#technical-details)

---

## What is the Helper?

The `wifiwand-helper` is a small native macOS application written in Swift that wifi-wand uses to retrieve WiFi network information (SSID, BSSID, signal strength, etc.) on modern versions of macOS.

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

Starting with **macOS Sonoma (14.0)** (and continuing in Sequoia 15.x), Apple requires additional authorization before command-line tools can see WiFi metadata:

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
Once the calling process (for example, Terminal.app) is approved for Location Services, those tools return the full SSID again—but approval is scoped per executable. Your shell might work while `/usr/bin/ruby` (or a CI runner) is still blocked, which is why the helper remains necessary.

### What Changed?

1. **SSID Redaction by Default**: Command-line tools like `networksetup` and `system_profiler` return `<redacted>` or blank values until the calling process is granted Location Services access.

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

> When installing the gem on macOS, wifi-wand prints a reminder pointing back to this document so you know how to grant Location Services access after the helper runs the first time.

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

- The first wifi-wand command that needs WiFi details launches `wifiwand-helper`, and macOS immediately asks for Location Services access.
- The dialog can appear behind other windows; if the command seems stuck, look for the prompt or open **System Settings → Privacy & Security → Location Services** to grant access manually once the helper appears there.
- macOS does **not** list `wifiwand-helper` in Location Services until the helper has run at least once. If you prefer to grant permission before using wifi-wand interactively, run:
  ```bash
  bundle exec rake mac:helper_location_permission_allow
  ```
  This task starts the helper briefly so macOS can register it, then waits for you to click **Allow** (or you can flip the switch in System Settings afterwards).

---

## Managing Permissions

wifi-wand provides rake tasks to manage Location Services permissions for the helper.

### Check Current Permission Status

```bash
rake mac:helper_location_permission_status
```

**Output:**
```
No Location Services entry found for wifiwand-helper.
```
or
```
Location Services entries for wifiwand-helper:
- Allowed (auth=2) for com.wifiwand.helper [bundle identifier] at 2025-11-03 10:00:00
```

### Grant Location Permission

```bash
rake mac:helper_location_permission_allow
```

This will:
1. Reset any existing permission decision
2. Launch the helper (which causes macOS to list it under Location Services if this is the first run)
3. Trigger the macOS permission prompt
4. Wait for you to click "Allow"

**What you'll see:**
```
"wifiwand-helper" would like to access your location.

wifiwand needs location access to retrieve Wi-Fi network information.

[Don't Allow]  [Allow]
```

Click **Allow** to grant permission.

### Revoke Location Permission

```bash
rake mac:helper_location_permission_deny
```

This prompts you to click **Don't Allow** when the permission dialog appears.

### Reset Permission

```bash
rake mac:helper_location_permission_reset
```

This clears the stored permission decision, allowing you to re-authorize.

### Manual Permission Management

You can also manage permissions via System Settings:

1. Open **System Settings**
2. Go to **Privacy & Security → Location Services**
3. Scroll to find **wifiwand-helper** or **com.wifiwand.helper** (the helper only appears here after it has run once—run any wifi-wand command that talks to WiFi or use `bundle exec rake mac:helper_location_permission_allow` to seed the entry)
4. Toggle permission on/off

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
# Check permission
rake mac:helper_location_permission_status

# Grant permission if needed
rake mac:helper_location_permission_allow

# Check system Location Services
open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
```

---

### Permission Prompt Doesn't Appear

**Symptom:** Run `rake mac:helper_location_permission_allow` but no prompt shows

**Possible Causes:**
1. Permission already granted or denied
2. Helper not properly installed
3. macOS caching the previous decision

**Solution:**
```bash
# Reset the permission
rake mac:helper_location_permission_reset

# Try again
rake mac:helper_location_permission_allow

# If still no prompt, reinstall helper
rm -rf ~/Library/Application\ Support/WifiWand/
# Run any wifi-wand command to reinstall
wifi-wand info
```

---

### "Helper Installation Failed"

**Symptom:** Error message about helper installation failure

**Possible Causes:**
1. Swift compiler not available (shouldn't happen with pre-signed binary)
2. Corrupted helper files
3. File permission issues

**Solution:**
```bash
# Remove old helper
rm -rf ~/Library/Application\ Support/WifiWand/

# Check if Xcode Command Line Tools are installed
xcode-select -p

# If not installed:
xcode-select --install

# Try running wifi-wand again
wifi-wand info
```

---

### Helper Works Without Permission?

**Observation:** On some macOS versions (notably 15.6.1), the helper successfully returns WiFi information without creating a persistent TCC entry.

**Why this happens:**
This appears to be a quirk of macOS 15.x behavior where:
- The helper receives temporary authorization per-execution
- Authorization is not stored persistently in the TCC database
- WiFi information is still successfully retrieved

**Is this a problem?**
Not really - it means wifi-wand works without requiring explicit permission management. However, for proper long-term behavior and user control, using the permission rake tasks is still recommended.

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

**You are in full control.** The helper only runs when you use wifi-wand, and you can revoke permissions at any time.

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
2. Checks if helper exists at `~/Library/Application Support/WifiWand/{version}/`
3. If not found, copies pre-signed helper from gem installation
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

Old versions are not automatically removed (in case you have multiple wifi-wand versions installed). You can safely delete old version directories.

### Disabling the Helper

If you prefer not to use the helper (accepting that WiFi names will be redacted), set:
```bash
export WIFIWAND_DISABLE_MAC_HELPER=1
```

wifi-wand will fall back to traditional methods and will typically show `<redacted>` for network names on macOS 14+ unless the invoking process already has Location Services approval.

---

## For Gem Maintainers

If you're interested in the code signing and notarization process used to build the helper, see the maintainer documentation in the repository:
- **[docs/dev/MACOS_CODE_SIGNING.md](https://github.com/keithrbennett/wifiwand/blob/main/docs/dev/MACOS_CODE_SIGNING.md)** (not included in gem distribution)

---

## Additional Resources

- [wifi-wand Repository](https://github.com/keithrbennett/wifiwand)
- [Report Issues](https://github.com/keithrbennett/wifiwand/issues)
- [Apple Developer: Protecting User Privacy](https://developer.apple.com/documentation/corelocation/protecting_user_privacy)
- [Apple Support: Location Services](https://support.apple.com/guide/mac-help/change-location-services-settings-mh35873/mac)

---

**Last Updated:** 2025-11-03
**macOS Compatibility:** macOS 14.0 (Sonoma) and later
**Helper Version:** Matches wifi-wand gem version
