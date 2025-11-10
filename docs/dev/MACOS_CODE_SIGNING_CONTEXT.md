# macOS Code Signing Context and Reference for wifi-wand

> Audience: wifi-wand maintainers preparing signed and notarized helpers.

---

## Table of Contents

- [Background and Context](#background-and-context)
- [Why Code Signing is Required](#why-code-signing-is-required)
- [Development vs Distribution](#development-vs-distribution)
- [Getting an Apple Developer ID](#getting-an-apple-developer-id)
- [Managing Credentials with 1Password CLI (Recommended)](#managing-credentials-with-1password-cli-recommended)
- [Signing and Notarization Workflow](#signing-and-notarization-workflow)
- [Rake Tasks Reference](#rake-tasks-reference)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Background and Context

### The macOS 15.x SSID Redaction Problem

Starting with **macOS Sonoma (14.0)** and continuing in **macOS Sequoia (15.x)**, Apple introduced significant security changes to WiFi network information access:

1. **SSID/BSSID redaction by default**: Command-line tools like `networksetup` and `system_profiler` return `<redacted>` or empty values until the calling process has Location Services authorization.
2. **Location Services requirement**: The CoreWLAN framework (which provides programmatic WiFi access) now requires Location Services authorization to return unredacted SSID information
3. **TCC (Transparency, Consent, and Control) enforcement**: macOS strictly manages which applications can access location data through the TCC database

Once a shell or application is granted Location Services access, the legacy tools resume returning real SSIDs—but that approval is scoped to the specific binary. Terminal.app might already be approved while `/usr/bin/ruby` (or your CI runner) is not, which is why the helper still matters.

### Why wifi-wand Needs a Helper Application

Because of these restrictions, `wifi-wand` cannot directly access WiFi information from Ruby. The solution is a native macOS helper application written in Swift that:

- Uses the CoreWLAN framework to access WiFi interfaces
- Requests Location Services authorization via CoreLocation
- Returns unredacted SSID/BSSID information as JSON
- Operates as a separate process that can be properly managed by TCC

### The Authorization Mystery on macOS 15.6.1

During development, we discovered unexpected behavior on **macOS 15.6.1**:

- The helper receives `authorizedAlways` status (value 3) from CoreLocation
- WiFi information is successfully retrieved without redaction
- **However, no TCC database entry is created**
- Authorization appears to be ephemeral/temporary, granted per-execution

This behavior is inconsistent with documented macOS TCC requirements and may be:
- A macOS 15.x bug or quirk
- Temporary authorization for apps with proper Info.plist keys
- Development mode behavior

**Note:** wifi-wand now requires Developer ID signing for the helper. The temporary authorization observed above is not reliable enough for production use, and permission management requires persistent TCC entries that only proper code signing provides.

**With Developer ID signing**, you get:
- Persistent TCC entries are created
- Users can manage permissions via System Settings
- The helper works reliably across all macOS configurations
- Professional deployment without Gatekeeper warnings

---

## Why Code Signing is Required

### Code Signing Purposes

Code signing serves multiple critical purposes:

1. **Identity Verification**: Proves the app comes from a known developer
2. **Integrity Protection**: Ensures the app hasn't been tampered with
3. **TCC Registration**: Allows macOS to create persistent permission entries
4. **Gatekeeper Approval**: Prevents "unidentified developer" warnings
5. **Permission Management**: Enables users to control app permissions via System Settings

### Developer ID Code Signing Required

The wifiwand helper **requires** proper code signing with a Developer ID certificate. Ad-hoc signing (using `-` as the identity) does **not** work for this use case because:

- ❌ Ad-hoc signing does not create persistent TCC database entries
- ❌ Permission management rake tasks cannot function
- ❌ Users cannot control permissions via System Settings
- ❌ Helper authorization is unreliable

**Developer ID Signing:**

```bash
codesign --sign "Developer ID Application: Your Name (TEAM123)" \
  --options runtime \
  --entitlements wifiwand-helper.entitlements \
  --timestamp \
  wifiwand-helper.app
```

**What you get:**
- ✅ Identifies you as the developer
- ✅ Can be notarized by Apple
- ✅ Creates persistent TCC entries
- ✅ No Gatekeeper warnings
- ✅ Professional distribution
- ✅ Permission management works correctly
- ✅ Meets enterprise requirements

**Requirements:**
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate

---

## Development vs Distribution

### For Development (End Users)

When users install the `wifi-wand` gem, they receive a **pre-signed, pre-notarized** helper binary:

1. Gem is installed via `gem install wifi-wand`
2. Helper binary (already signed by you) is extracted to `~/Library/Application Support/WifiWand/`
3. Helper works immediately with proper TCC support
4. Users can manage permissions via System Settings → Privacy & Security → Location Services

**Users never need to sign or compile anything.**

### For Distribution (Gem Maintainer)

As the gem maintainer, you perform signing and notarization **before releasing** a new gem version:

```bash
# 1. Sign with your Developer ID (uses values from lib/wifi-wand/mac_helper_release.rb)
bundle exec rake dev:build_signed_helper

# 2. Notarize with Apple
WIFIWAND_APPLE_DEV_ID="you@example.com" \
WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  bundle exec rake dev:notarize_helper

# 3. Commit the signed binary
git add libexec/macos/wifiwand-helper.app
git commit -m "Update signed and notarized macOS helper"

# 4. Build and release gem
gem build wifi-wand.gemspec
gem push wifi-wand-X.Y.Z.gem
```

The signed binary is committed to git and distributed with the gem.

---

## Getting an Apple Developer ID

### Step 1: Join the Apple Developer Program

1. Visit https://developer.apple.com/programs/
2. Click "Enroll"
3. Sign in with your Apple ID
4. Pay the $99/year membership fee
5. Wait for approval (usually 1-2 business days)

### Step 2: Request a Developer ID Certificate

#### Option A: Using Xcode (Recommended)

1. Open Xcode
2. Go to **Xcode → Settings → Accounts**
3. Click **+** to add your Apple ID
4. Select your account, click **Manage Certificates**
5. Click **+** and choose **Developer ID Application**
6. Certificate is automatically created and installed

#### Option B: Using Keychain Access

1. Open **Keychain Access** (Applications → Utilities)
2. Go to **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority**
3. Enter your email address
4. Choose **Saved to disk**
5. Save the Certificate Signing Request (CSR)
6. Visit https://developer.apple.com/account/resources/certificates/add
7. Choose **Developer ID Application**
8. Upload your CSR
9. Download and double-click the certificate to install

### Step 3: Verify Your Certificate

```bash
# List all code signing identities
security find-identity -v -p codesigning
```

You should see something like:
```
1) A1B2C3D4E5F6... "Developer ID Application: Your Name (TEAM123)"
```

Copy the full identity string (inside the quotes) — you'll paste it into the `CODESIGN_IDENTITY` constant in `lib/wifi-wand/mac_helper_release.rb`. The 10-character suffix in parentheses is your Apple Team ID; confirm it matches the value shown on developer.apple.com because you'll set `APPLE_TEAM_ID` to that exact string.

### Step 4: Update Hardcoded Public Values

Edit `lib/wifi-wand/mac_helper_release.rb` and replace the placeholders with your real values:

```ruby
# Public signing credentials (visible in all signed binaries - no need to hide)
APPLE_TEAM_ID = 'TEAM123ABCD'
CODESIGN_IDENTITY = 'Developer ID Application: Your Name (TEAM123ABCD)'
```

These values are public (visible in all signed binaries via `codesign -dv`), so they don't need to be hidden in 1Password. Update them whenever you switch to a different Developer ID certificate.

### Step 5: Create an App-Specific Password

For notarization, you need an app-specific password:

1. Visit https://appleid.apple.com
2. Sign in with your Apple ID
3. Go to **Security → App-Specific Passwords**
4. Click **+** to generate a new password
5. Enter a label (e.g., "wifi-wand notarization")
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

---

## Managing Credentials with 1Password CLI (Recommended)

For better security and convenience, you can use [1Password CLI](https://developer.1password.com/docs/cli) to manage your signing credentials.

### Benefits

- **Security**: No plaintext credentials in shell history or environment
- **Convenience**: One command instead of setting multiple environment variables
- **Audit Trail**: 1Password logs all secret access
- **Team Sharing**: Share credential references without exposing actual values
- **No Git Exposure**: `.env.release` contains only references, safe to commit

### Setup (One-time)

#### 1. Install 1Password CLI

```bash
# macOS (Homebrew)
brew install --cask 1password-cli

# Or download from https://1password.com/downloads/command-line/
```

#### 2. Sign in to 1Password

```bash
# Sign in (first time)
op signin

# Or if already configured
eval $(op signin)
```

#### 3. Create a 1Password Item

Create (or rename) a Secure Note in your vault. Keeping the item name lowercase with no spaces avoids escaping headaches later.

1. Open 1Password.
2. Choose **Secure Note** as the item type (or edit your existing note).
3. Name it **`wifiwand-release`**.
4. Add structured fields so the CLI can target them:
   - **APPLE_DEV_ID** (type **Text**): `you@example.com`
   - **APPLE_DEV_PASSWORD** (type **Password**): `xxxx-xxxx-xxxx-xxxx`
5. Leave any additional narrative text or attachments (like `.p12` exports) in the same item as needed.
6. Save to the vault you plan to reference (personal accounts usually default to **Personal**, shared accounts often use **Private**).

> **Note**: Team ID and codesign identity live directly in `lib/wifi-wand/mac_helper_release.rb`. They're public values (visible in signed binaries), so you only need to copy them into 1Password if it helps documentation or coordination.

#### 4. Edit `.env.release`

The repository now includes `.env.release` directly; treat it as the template plus configuration file. Open it and set the `op://` references to match your vault/item/field names. Example for a personal account:

```bash
# Private credentials only - Team ID and identity live in lib/wifi-wand/mac_helper_release.rb
WIFIWAND_APPLE_DEV_ID=op://Personal/wifiwand-release/APPLE_DEV_ID
WIFIWAND_APPLE_DEV_PASSWORD=op://Personal/wifiwand-release/APPLE_DEV_PASSWORD
```

If your vault is named differently (e.g., `Private` or a team-specific vault), change the path accordingly.

### Usage

#### Using `op run` with 1Password CLI

```bash
# Sign only
op run --env-file=.env.release -- bundle exec rake dev:build_signed_helper

# Complete workflow (sign, test, notarize)
op run --env-file=.env.release -- bundle exec rake dev:release_helper

# Individual notarization
op run --env-file=.env.release -- bundle exec rake dev:notarize_helper
```

#### How It Works

1. **`op run`** reads `.env.release`
2. Fetches actual values from your 1Password vault
3. Sets environment variables with real values
4. Runs the command (rake task)
5. Command completes, variables disappear
6. No secrets left in shell history or environment

### Fallback to Direct Environment Variables

If you don't use 1Password, you can still set environment variables directly:

```bash
# Private credentials only - Team ID and identity live in lib/wifi-wand/mac_helper_release.rb
export WIFIWAND_APPLE_DEV_ID="you@example.com"
export WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx"

bundle exec rake dev:release_helper
```

The rake tasks work identically with either approach.

---

## Signing and Notarization Workflow

### Complete Release Workflow

**Option 1: Using 1Password CLI (Recommended)**

```bash
# Complete workflow with 1Password
op run --env-file=.env.release -- bundle exec rake dev:release_helper
```

**Option 2: Using Environment Variables**

```bash
# Set private credentials (team ID and codesign identity are hardcoded in lib/wifi-wand/mac_helper_release.rb)
export WIFIWAND_APPLE_DEV_ID="you@example.com"
export WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# Run complete workflow
bundle exec rake dev:release_helper
```

**What this does:**
1. ✅ Compiles the Swift helper
2. ✅ Signs with your Developer ID
3. ✅ Tests the signed binary
4. ✅ Uploads to Apple for notarization
5. ✅ Waits for approval (~2-5 minutes)
6. ✅ Staples the notarization ticket
7. ✅ Verifies everything works

### Individual Steps (if needed)

#### Step 1: Build and Sign

```bash
bundle exec rake dev:build_signed_helper
```

This compiles the helper and signs it with:
- Your Developer ID certificate
- Hardened Runtime enabled
- Entitlements file applied
- Secure timestamp

#### Step 2: Test the Signed Helper

```bash
bundle exec rake dev:test_signed_helper
```

This verifies:
- Code signature is valid
- Bundle identifier is correct
- Helper executes successfully
- CoreWLAN returns unredacted WiFi info

#### Step 3: Notarize with Apple

```bash
WIFIWAND_APPLE_DEV_ID="you@example.com" \
WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  bundle exec rake dev:notarize_helper
```

This:
- Creates a zip archive of the helper
- Submits to Apple's notarization service
- Waits for approval
- Staples the notarization ticket to the app

#### Step 4: Check Status

```bash
bundle exec rake dev:codesign_status
```

Shows:
- Signature details
- Verification status
- Notarization status
- Gatekeeper assessment

### After Successful Notarization

```bash
# Commit the signed helper
git add libexec/macos/wifiwand-helper.app
git commit -m "Update signed and notarized macOS helper for version X.Y.Z"

# Update version if needed
# Edit lib/wifi-wand/version.rb

# Build gem
gem build wifi-wand.gemspec

# Test the gem locally
gem install wifi-wand-X.Y.Z.gem --local

# Publish to RubyGems
gem push wifi-wand-X.Y.Z.gem
```

---

## Rake Tasks Reference

All developer tasks are in the `dev:` namespace and are **not included in the distributed gem**.

### `dev:build_signed_helper`

**Purpose:** Compile and sign the helper with Developer ID (uses the credentials in `lib/wifi-wand/mac_helper_release.rb`)

**Environment Variables:** None

**Example:**
```bash
bundle exec rake dev:build_signed_helper
```

**Output:**
- Compiled binary: `libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper`
- Signed with Developer ID
- Hardened Runtime enabled
- Entitlements applied

---

### `dev:test_signed_helper`

**Purpose:** Test the signed helper binary

**Environment Variables:** None

**Example:**
```bash
bundle exec rake dev:test_signed_helper
```

**Checks:**
- Code signature validity
- Bundle identifier
- Helper execution
- WiFi information retrieval

> **Prerequisite:** macOS only lists `wifiwand-helper` in Location Services after the helper runs once (for example via `bundle exec rake mac:helper_location_permission_allow`). Make sure it appears under **System Settings → Privacy & Security → Location Services** and toggle it on before running the test to avoid a hidden prompt that makes the task appear stuck.

---

### `dev:notarize_helper`

**Purpose:** Submit helper to Apple for notarization

**Environment Variables:**
- `WIFIWAND_APPLE_DEV_ID` (required) - Your Apple ID email
- `WIFIWAND_APPLE_DEV_PASSWORD` (required) - App-specific password

**Note:** Team ID is hardcoded in `lib/wifi-wand/mac_helper_release.rb` (it's a public value visible in signed binaries).

**Example:**
```bash
WIFIWAND_APPLE_DEV_ID="you@example.com" \
WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  bundle exec rake dev:notarize_helper
```

**Process:**
1. Creates zip archive
2. Submits to Apple
3. Polls for status (usually 2-5 minutes)
4. Staples ticket on success

If the task exits early (for example because `notarytool --wait` timed out) but you later confirm the submission shows `Accepted`, staple manually:
```
xcrun stapler staple libexec/macos/wifiwand-helper.app
```

---

### `dev:release_helper`

**Purpose:** Complete workflow (build, sign, test, notarize)

**Environment Variables:**
- `WIFIWAND_APPLE_DEV_ID` (required) - Your Apple ID email
- `WIFIWAND_APPLE_DEV_PASSWORD` (required) - App-specific password

**Note:** Team ID is hardcoded in `lib/wifi-wand/mac_helper_release.rb` (it's a public value visible in signed binaries).

**Example:**
```bash
WIFIWAND_APPLE_DEV_ID="you@example.com" \
WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  bundle exec rake dev:release_helper
```

**This is the recommended command for releases.**

---

### `dev:codesign_status`

**Purpose:** Show current code signing and notarization status

**Environment Variables:** None

**Example:**
```bash
bundle exec rake dev:codesign_status
```

**Output:**
- Signature details
- Verification result
- Notarization status
- Gatekeeper assessment

---

### `dev:notarization_history`

**Purpose:** Show the most recent notarization submissions tied to your Apple ID and team. Helpful when `dev:notarize_helper` appears to hang.

**Environment Variables:**
- `WIFIWAND_APPLE_DEV_ID` (required)
- `WIFIWAND_APPLE_DEV_PASSWORD` (required)

**Example:**
```bash
op run --env-file=.env.release -- bundle exec rake dev:notarization_history
```

**Output:** `xcrun notarytool history` table with submission IDs, dates, and states.

---

### `dev:notarization_status`

**Purpose:** Show the current status for a submission (accepted, in progress, invalid, etc.).

**Environment Variables:** Same as above. `SUBMISSION_ID=<uuid>` (or `ID`/`NOTARY_ID`) is optional—if omitted, the task automatically selects the newest submission from `notarytool history`, preferring one that is still `In Progress`.

**Example:**
```bash
# Auto-select most recent submission
op run --env-file=.env.release -- bundle exec rake dev:notarization_status

# Or specify an explicit ID
op run --env-file=.env.release -- \
  env SUBMISSION_ID=12345678-90AB-CDEF-1234-567890ABCDEF \
  bundle exec rake dev:notarization_status
```

**Output:** The detailed `xcrun notarytool info` report for that submission.

---

### `dev:notarization_log`

**Purpose:** Fetch the full notarization log for a submission (useful when Apple rejects the upload).

**Environment Variables:** Same as `dev:notarization_status`; `SUBMISSION_ID` is optional and falls back to the latest submission if omitted.

**Example:**
```bash
# Auto-select most recent submission
op run --env-file=.env.release -- bundle exec rake dev:notarization_log

# Or specify an explicit ID
op run --env-file=.env.release -- \
  env SUBMISSION_ID=12345678-90AB-CDEF-1234-567890ABCDEF \
  bundle exec rake dev:notarization_log
```

**Output:** The JSON/diagnostic log Apple provides, streamed to stdout for easier debugging.

---

## Troubleshooting

### "No such bundle identifier" (tccutil error)

**Symptom:**
```
tccutil: No such bundle identifier "com.wifiwand.helper"
```

**Cause:** Helper is not properly signed or bundle doesn't exist

**Solution:**
```bash
# Recompile and sign
bundle exec rake swift:compile_helper

# Check signature
codesign -dvv libexec/macos/wifiwand-helper.app
```

---

### "Unable to find code signing identity"

**Symptom:**
```
Error: Could not find code signing identity 'Developer ID Application: ...'
```

**Cause:** Certificate not installed or name incorrect

**Solution:**
```bash
# List available identities
security find-identity -v -p codesigning

# Use exact name from output (update CODESIGN_IDENTITY in lib/wifi-wand/mac_helper_release.rb)
bundle exec rake dev:build_signed_helper
```

---

### "Notarization failed - Invalid"

**Symptom:**
```
status: Invalid
```

**Cause:** Helper not properly signed for notarization

**Solution:**
1. Ensure you're using Developer ID (not ad-hoc `-`)
2. Verify hardened runtime is enabled
3. Check entitlements are applied

```bash
# Rebuild with correct signing (after updating CODESIGN_IDENTITY in lib/wifi-wand/mac_helper_release.rb)
bundle exec rake dev:build_signed_helper

# Verify before notarizing
codesign -dvv libexec/macos/wifiwand-helper.app | grep runtime
```

---

### "Helper returns <redacted> SSID"

**Symptom:** Helper returns `null` or empty SSID/BSSID

**Possible Causes:**
1. Helper doesn't have Location Services permission
2. Helper is not properly signed
3. Location Services disabled system-wide

**Solution:**
```bash
# Check TCC entry
bundle exec rake mac:helper_location_permission_status

# Grant permission
bundle exec rake mac:helper_location_permission_allow

# Check system Location Services
open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
```

---

### "xcrun: error: unable to find utility 'notarytool'"

**Symptom:** Notarization fails with `notarytool` not found

**Cause:** Xcode Command Line Tools not installed or outdated

**Solution:**
```bash
# Install or update Command Line Tools
xcode-select --install

# Or update via Software Update
softwareupdate --install --all
```

---

## FAQ

### Do end users need an Apple Developer ID?

**No.** End users install the pre-signed gem and never need to sign anything.

### Why is the signed binary committed to git?

So that users get a working, signed helper when they install the gem. Without this, users would need to compile and sign it themselves, which is impractical.

### How often do I need to re-notarize?

Every time you release a new gem version with an updated helper. The binary's hash changes with each compilation, requiring new notarization.

### Can I use the same Developer ID for multiple projects?

Yes. A single Developer ID certificate can sign unlimited applications.

### Does the $99/year Apple Developer membership auto-renew?

Yes, unless you disable auto-renewal in your Apple ID account settings.

### What happens if my Developer ID certificate expires?

- Your certificate expires after 5 years
- Apps signed with expired certificates still work
- You'll need to renew the certificate to sign new releases
- Apple automatically creates a new certificate when the old one nears expiration

### Can I distribute a debug/development build?

No. wifi-wand requires properly signed helpers because:
- Ad-hoc signing does not create TCC database entries
- Permission management does not function without TCC entries
- Users cannot control permissions
- The helper's behavior is unreliable

Always use your Developer ID certificate, even for development/testing, to ensure proper TCC integration.

### How do I rotate my app-specific password?

1. Revoke old password at https://appleid.apple.com
2. Generate new password
3. Update your environment variables
4. Re-run notarization

### What if Apple rejects notarization?

Check the detailed logs:
```bash
# Get submission ID from failed output
xcrun notarytool log SUBMISSION_ID \
  --apple-id you@example.com \
  --team-id TEAM123 \
  --password xxxx-xxxx-xxxx-xxxx
```

Common issues:
- Missing entitlements
- Hardened runtime not enabled
- Unsigned dependencies
- Invalid Info.plist

---

## Additional Resources

- [Apple Developer Documentation - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple Developer Documentation - Code Signing](https://developer.apple.com/support/code-signing/)
- [Apple Developer Documentation - Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [TN3147: Code signing and notarizing issues](https://developer.apple.com/documentation/technotes/tn3147-resolving-common-notarization-issues)
- [wifi-wand Repository](https://github.com/keithrbennett/wifiwand)

---

**Last Updated:** 2025-11-03
**macOS Version:** Tested on macOS 15.6.1 (Sequoia)
**Xcode Version:** Compatible with Xcode 15.0+
