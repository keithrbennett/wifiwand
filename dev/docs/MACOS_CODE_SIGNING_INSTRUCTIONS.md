# macOS Code Signing Instructions for wifiwand

> Audience: wifiwand maintainers who need to produce the signed and notarized `wifiwand-helper.app` that
> ships with each gem release.

This page is intentionally short so you can follow it during a release. When you need the “why” behind any
step (or deeper troubleshooting), jump to `MACOS_CODE_SIGNING_CONTEXT.md`.

---

## Before You Start

- Active Apple Developer Program membership (the $99/year account you already use for Developer ID
  certificates).
- Xcode Command Line Tools installed (`xcode-select --install`) so `codesign`, `notarytool`, etc. are
  available.
- Ruby environment that can run `bin/mac-helper-release` (no bundler required for the script itself).
- The official maintainer Developer ID certificate installed in the local macOS keychain.

## Helper Update Policy

The committed `libexec/macos/wifiwand-helper.app` is the signed and notarized helper that ships with the gem.
We update that helper bundle during release work, not for every intermediate source edit. This keeps the
checked-in distribution artifact tied to a deliberate gem release and avoids asking users who build from
source to produce their own signed macOS app.

Run the helper release workflow when either condition is true:

- You are cutting a new wifiwand gem release.
- You changed helper Swift source, helper entitlements, or committed helper bundle metadata and that change
  must ship in the next release.

For source-only development that does not change the helper, use `bin/mac-helper-release verify` or
`bundle exec rake swift:verify_helper_attestation` to confirm the committed bundle still matches its
attestation manifest. On macOS release machines, use `bundle exec rake swift:verify_helper` when you want the
aggregate check that verifies both source attestation and the committed helper's code signature. Do not
refresh and commit `libexec/macos/wifiwand-helper.app` outside release work unless there is an explicit reason
to ship a replacement helper.

People who clone the repository can build the Ruby gem without an Apple Developer ID as long as they do not
rebuild the macOS helper. Rebuilding a working helper app requires macOS, Xcode Command Line Tools, and a
Developer ID Application certificate. Official releases use the maintainer certificate; local, non-release
experiments may use `WIFIWAND_APPLE_TEAM_ID` and `WIFIWAND_CODESIGN_IDENTITY` to point at another Developer
ID identity.

## Signing Assets Summary

| Item | Kind | Where It Lives | How It Is Created / Updated | Secret? | Notes |
| --- | --- | --- | --- | --- | --- |
| Developer ID Application certificate | Apple signing identity | macOS keychain | Create via Xcode or Keychain Access | No | Used by `codesign` during helper signing |
| Apple Team ID | Public team identifier | Official release helper default; optional `WIFIWAND_APPLE_TEAM_ID` override | Copy from Apple Developer membership / certificate metadata | No | Required for official signing and notarization commands |
| Codesign identity string | Public signing config | Official release helper default; optional `WIFIWAND_CODESIGN_IDENTITY` override | Copy exact identity from `security find-identity -v -p codesigning` | No | Must match the official maintainer Developer ID certificate |
| Apple app-specific password | Apple credential | Apple account UI, then local entry at setup time | Create at `appleid.apple.com` | Yes | Apple only shows it once |
| `notarytool` keychain profile | Local notarization credential reference | Login keychain by default | `bin/mac-helper-release store-credentials` or raw `xcrun notarytool store-credentials ...` | Contains secret material indirectly | Runtime commands use the profile name, not the password |
| `WIFIWAND_NOTARYTOOL_PROFILE` | Local runtime config | Shell env / `.env.release` | Set only if you want a non-default profile name | No | Defaults to `wifiwand-notarytool` |
| `WIFIWAND_NOTARYTOOL_KEYCHAIN` | Local runtime config | Shell env / `.env.release` | Set only if you use a non-default keychain | No | Optional override |
| Signed helper bundle | Release artifact | `libexec/macos/wifiwand-helper.app` | `bin/mac-helper-release build` / `bin/mac-helper-release release` | No | This is the bundle shipped with the gem |
| Helper source manifest | Attestation metadata | `libexec/macos/wifiwand-helper.source-manifest.json` | Rewritten during helper build/sign flow | No | Tracks the relationship between source and committed bundle |

---

## First-Time Setup Checklist

1. **Enroll & verify your Developer ID certificate**
   - Enroll at https://developer.apple.com/programs/.
   - Create a *Developer ID Application* certificate via Xcode (`Xcode → Settings → Accounts → Manage
     Certificates → +`) or Keychain Access.
   - Confirm macOS can see the identity:
     ```bash
     security find-identity -v -p codesigning
     ```
     Copy the exact identity string (e.g., `Developer ID Application: Your Name (TEAM123ABCD)`).

2. **Confirm the official public signing values**
   - Official wifiwand release helpers must use the project maintainer's Developer ID.
   - The release helper source tracks the public Team ID and codesign identity used for official releases.
   - If the official certificate changes, update those tracked official defaults as part of that release.
   - For local, non-distribution signing experiments only, override with `WIFIWAND_APPLE_TEAM_ID` and
     `WIFIWAND_CODESIGN_IDENTITY` instead of changing the official defaults.

3. **Generate the notarization password**
   - Visit https://appleid.apple.com → *Security → App-Specific Passwords* → `+`.
   - Label it “wifiwand notarization” (or similar) and copy the `xxxx-xxxx-xxxx-xxxx` password.

4. **Store a secure `notarytool` profile in your keychain**
   - Inspect the public signing configuration if needed:
     ```bash
     bin/mac-helper-release public-info
     ```
   - Store credentials with the maintainer CLI:
     ```bash
     bin/mac-helper-release store-credentials
     ```
   - Or run the equivalent raw command:
     ```bash
     xcrun notarytool store-credentials wifiwand-notarytool --apple-id you@example.com --team-id TEAM123ABCD
     ```
   - `bin/mac-helper-release store-credentials` prompts for the Apple ID if needed, and `notarytool` prompts
     for the app-specific password instead of taking it on the command line.
   - If you use a non-default keychain, unlock it first and set `WIFIWAND_NOTARYTOOL_KEYCHAIN` when running
     `bin/mac-helper-release`.
   - If you want to use a different profile name, set `WIFIWAND_NOTARYTOOL_PROFILE`.
   - The checked-in `.env.release` file now documents the non-secret profile configuration rather than storing
     runtime notarization secrets.

5. **Dry run the workflow once**
   ```bash
   bin/mac-helper-release build
   ```
   - Confirms the helper builds, signs, and that your local keychain trusts the certificate.
   - Run the helper once so macOS registers it with Location Services. For maintainer/dev workflows,
     `bin/mac-helper-release test` is sufficient. For the shipped end-user flow, use
     `wifiwand-macos-setup` instead
     of any repo-local rake task.
   - After the helper shows up under
     **System Settings → Privacy & Security → Location Services**, toggle it on to avoid the
     hidden prompt the first time the test task runs.

6. **Follow the build task's suggested next steps**
   - Test the signed helper: `bin/mac-helper-release test`
   - Notarize (uses keychain profile): `bin/mac-helper-release notarize`
   - If the notarize task exits before stapling—even though Apple later accepts the submission—run `xcrun
     stapler staple libexec/macos/wifiwand-helper.app` yourself once notarization status reports `Accepted`
   - Commit the updated `libexec/macos/wifiwand-helper.app` and proceed with gem build/release as usual

You are now ready to ship signed helpers on demand.

---

## Subsequent Code Signings (Every Release)

Follow the same sequence each time you change the helper or cut a gem release.

1. **Update the helper (if needed)**
   - Make Swift/Ruby changes as usual.
   - Ensure the tracked official signing defaults still match the maintainer certificate.

2. **Run the release automation (preferred path)**
   ```bash
   bin/mac-helper-release release
   ```
   What it does:
   1. Builds the helper
   2. Signs with your Developer ID
   3. Tests the signed bundle
   4. Notarizes with Apple and staples the ticket
3. **Spot-check when needed**
   ```bash
   bin/mac-helper-release status
   ```
   Shows signature, hardened runtime, and notarization status.

4. **Run the maintainer release checklist**
   ```bash
   # Update lib/wifi_wand/version.rb first if this release changes the gem version.
   git add libexec/macos/wifiwand-helper.app \
     libexec/macos/wifiwand-helper.source-manifest.json \
     lib/wifi_wand/version.rb
   git commit -m "Update signed and notarized macOS helper for <version>"
   bundle exec rake test
   bundle exec rake build
   tar -xOf pkg/wifi-wand-<version>.gem data.tar.gz | tar -tz  # wifi-wand is the gem package name
   # Do not edit after inspecting the payload; release rebuilds before pushing.
   bundle exec rake release build:checksum
   ```
   Before publishing, inspect the built gem payload and confirm it includes the required runtime files,
   executables, helper assets, and user-facing documents while excluding maintainer-only tooling. Use
   `bundle exec rake release build:checksum` for the RubyGems publish path. Keep the tree unchanged after the
   payload inspection because the release task rebuilds before pushing, then `build:checksum` generates the
   checksum from that same release-task build.

5. **If notarization stalls or fails**
   - Check Apple's queue: `bin/mac-helper-release history`
   - For a specific submission, run `bin/mac-helper-release info --submission-id <uuid>` (omit
     `--submission-id` to automatically target the most recent submission). This command wraps `xcrun
     notarytool info`.
   - Pull the detailed log with `bin/mac-helper-release log --submission-id <uuid>` (same auto-detection
     applies)
   - Cancel a stuck submission with `bin/mac-helper-release cancel` (only pending `In Progress`
     submissions can be removed; pass `--submission-id <uuid>` to target a specific one, or use `--order asc
     --pending-only` to cancel oldest pending)
   - If Apple reports a missing or expired agreement, accept it in the Apple Developer account, then wait a
     few minutes and retry `bin/mac-helper-release store-credentials`
   - If the submission was rejected, rebuild the helper (`bin/mac-helper-release build`) before re-running
     the release flow.

### Runtime configuration

The notarization commands now use only a keychain profile at runtime. Supported environment variables:

- `WIFIWAND_NOTARYTOOL_PROFILE` – override the profile name (default: `wifiwand-notarytool`)
- `WIFIWAND_NOTARYTOOL_KEYCHAIN` – point `notarytool` at a custom keychain file
- `WIFIWAND_APPLE_TEAM_ID` – optional Team ID override for local, non-release signing experiments
- `WIFIWAND_CODESIGN_IDENTITY` – optional codesign identity override for local, non-release signing
  experiments

Normal maintainer release commands use the tracked official signing defaults and do not require shell exports.

---

## Need More Detail?

- Background, troubleshooting, and the rationale for each requirement:
  `dev/docs/MACOS_CODE_SIGNING_CONTEXT.md`
- Password reset and agreement-troubleshooting note:
  `dev/docs/MACOS_NOTARYTOOL_PASSWORD_RESET.md`
- Script implementation lives in `bin/mac-helper-release` (CLI) and
  `lib/wifi_wand/platforms/mac/helper/release.rb` (core logic).
- Forget the commands? Run `bin/mac-helper-release help` for a quick reminder.

Keeping this file short makes it easier to execute the release without rereading the entire history every
time. Refer back to the context file whenever you need the "why."
