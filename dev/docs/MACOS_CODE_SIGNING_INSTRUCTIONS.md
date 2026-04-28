# macOS Code Signing Instructions for wifi-wand

> Audience: wifi-wand maintainers who need to produce the signed and notarized `wifiwand-helper.app` that
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
- Access to `lib/wifi-wand/mac_helper/mac_helper_release.rb` in the repo so you can update the public signing constants.

## Signing Assets Summary

| Item | Kind | Where It Lives | How It Is Created / Updated | Secret? | Notes |
| --- | --- | --- | --- | --- | --- |
| Developer ID Application certificate | Apple signing identity | macOS keychain | Create via Xcode or Keychain Access | No | Used by `codesign` during helper signing |
| Apple Team ID | Public team identifier | `lib/wifi-wand/mac_helper/mac_helper_release.rb` | Copy from Apple Developer membership / certificate metadata | No | Embedded in signed artifacts and safe to keep in source |
| Codesign identity string | Public signing config | `lib/wifi-wand/mac_helper/mac_helper_release.rb` | Copy exact identity from `security find-identity -v -p codesigning` | No | Must match the installed Developer ID certificate |
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

2. **Record the public values in the release helper**
   - Edit `lib/wifi-wand/mac_helper/mac_helper_release.rb` and replace `APPLE_TEAM_ID` and `CODESIGN_IDENTITY` with the
     values from the previous step.
   - These values are embedded in every signed binary, so storing them in git is expected.

3. **Generate the notarization password**
   - Visit https://appleid.apple.com → *Security → App-Specific Passwords* → `+`.
   - Label it “wifi-wand notarization” (or similar) and copy the `xxxx-xxxx-xxxx-xxxx` password.

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
     xcrun notarytool store-credentials wifiwand-notarytool --apple-id you@example.com --team-id 97P9SZU9GG
     ```
   - `bin/mac-helper-release store-credentials` prompts for the Apple ID if needed, and `notarytool` prompts for the
     app-specific password instead of taking it on the command line.
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
     `wifi-wand-macos-setup` instead
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
   - Ensure `APPLE_TEAM_ID`/`CODESIGN_IDENTITY` still match the certificate you intend to use.

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

4. **Commit & publish**
   ```bash
   git add libexec/macos/wifiwand-helper.app
   git commit -m "Update signed macOS helper for X.Y.Z"
   gem build wifi-wand.gemspec
   gem push wifi-wand-X.Y.Z.gem
   ```

5. **If notarization stalls or fails**
   - Check Apple's queue: `bin/mac-helper-release history`
   - For a specific submission, run `bin/mac-helper-release info --submission-id <uuid>` (omit
     `--submission-id` to automatically target the most recent submission). This command wraps `xcrun
     notarytool info`.
   - Pull the detailed log with `bin/mac-helper-release log --submission-id <uuid>` (same auto-detection applies)
   - Cancel a stuck submission with `bin/mac-helper-release cancel` (only pending `In Progress`
     submissions can be removed; pass `--submission-id <uuid>` to target a specific one, or use `--order asc
     --pending-only` to cancel oldest pending)
   - If Apple reports a missing or expired agreement, accept it in the Apple Developer account, then wait a
     few minutes and retry `bin/mac-helper-release store-credentials`
   - If the submission was rejected, rebuild the helper (`bin/mac-helper-release build`) before re-running
     the release flow.
     flow.

### Runtime configuration

The notarization commands now use only a keychain profile at runtime. Supported environment variables:

- `WIFIWAND_NOTARYTOOL_PROFILE` – override the profile name (default: `wifiwand-notarytool`)
- `WIFIWAND_NOTARYTOOL_KEYCHAIN` – point `notarytool` at a custom keychain file

---

## Need More Detail?

- Background, troubleshooting, and the rationale for each requirement:
  `dev/docs/MACOS_CODE_SIGNING_CONTEXT.md`
- Password reset and agreement-troubleshooting note:
  `dev/docs/MACOS_NOTARYTOOL_PASSWORD_RESET.md`
- Script implementation lives in `bin/mac-helper-release` (CLI) and
  `lib/wifi-wand/mac_helper/mac_helper_release.rb` (core logic).
- Forget the commands? Run `bin/mac-helper-release help` for a quick reminder.

Keeping this file short makes it easier to execute the release without rereading the entire history every
time. Refer back to the context file whenever you need the "why."
