# macOS Code Signing Instructions for wifi-wand

> Audience: wifi-wand maintainers who need to produce the signed and notarized `wifiwand-helper.app` that ships with each gem release.

This page is intentionally short so you can follow it during a release. When you need the “why” behind any step (or deeper troubleshooting), jump to `MACOS_CODE_SIGNING_CONTEXT.md`.

---

## Before You Start

- Active Apple Developer Program membership (the $99/year account you already use for Developer ID certificates).
- Xcode Command Line Tools installed (`xcode-select --install`) so `codesign`, `notarytool`, etc. are available.
- Ruby/Bundler environment that can run `bundle exec rake`.
- Access to `lib/wifi-wand/mac_helper_release.rb` in the repo so you can update the public signing constants.

---

## First-Time Setup Checklist

1. **Enroll & verify your Developer ID certificate**
   - Enroll at https://developer.apple.com/programs/.
   - Create a *Developer ID Application* certificate via Xcode (`Xcode → Settings → Accounts → Manage Certificates → +`) or Keychain Access.
   - Confirm macOS can see the identity:
     ```bash
     security find-identity -v -p codesigning
     ```
     Copy the exact identity string (e.g., `Developer ID Application: Your Name (TEAM123ABCD)`).

2. **Record the public values in the release helper**
   - Edit `lib/wifi-wand/mac_helper_release.rb` and replace `APPLE_TEAM_ID` and `CODESIGN_IDENTITY` with the values from the previous step.
   - These values are embedded in every signed binary, so storing them in git is expected.

3. **Generate the notarization password**
   - Visit https://appleid.apple.com → *Security → App-Specific Passwords* → `+`.
   - Label it “wifi-wand notarization” (or similar) and copy the `xxxx-xxxx-xxxx-xxxx` password.

4. **Store private credentials (recommended: 1Password CLI)**
  - Install the CLI: `brew install --cask 1password-cli`.
  - Authorize the CLI with `eval "$(op signin)"`. If it says no accounts are configured, run `op account add` (it will prompt for your sign-in address—individual accounts usually use `my.1password.com`, `my.1password.eu`, or `my.1password.ca`) and then re-run the `eval` command each new shell session.
  - Identify the vault name that contains your release secrets (for personal accounts the default is “Personal”; the desktop app shows it above the item name).
  - Rename or create a Secure Note called `wifiwand-release` (all lowercase, no spaces so the CLI path stays simple).
  - While editing that item, add structured fields so the CLI can read them:
    1. Click **Add field → Text**, name it `APPLE_DEV_ID`, paste your Apple ID email.
    2. Click **Add field → Password**, name it `APPLE_DEV_PASSWORD`, paste the app-specific password.
    3. Leave any narrative notes or attachments in the same item if helpful—the CLI ignores them.
  - Edit the checked-in `.env.release` file and point each entry at the vault/item/field you just defined (update `Personal` if your vault has a different name):
    ```bash
    WIFIWAND_APPLE_DEV_ID=op://Personal/wifiwand-release/APPLE_DEV_ID
    WIFIWAND_APPLE_DEV_PASSWORD=op://Personal/wifiwand-release/APPLE_DEV_PASSWORD
    ```
  - Prefer 1Password references so secrets never touch shell history; fall back to plain environment variables only if necessary.

5. **Dry run the workflow once**
   ```bash
   op run --env-file=.env.release -- bundle exec rake dev:build_signed_helper
   ```
   - Confirms the helper builds, signs, and that your local keychain trusts the certificate.
   - Run the helper once so macOS registers it with Location Services (either start `bundle exec rake dev:test_signed_helper` or run `bundle exec rake mac:helper_location_permission_allow`, which launches the helper just long enough to create the TCC entry).
   - After the helper shows up under **System Settings → Privacy & Security → Location Services**, toggle it on to avoid the hidden prompt the first time the test task runs.

6. **Follow the build task’s suggested next steps**
   - Test the signed helper: `bundle exec rake dev:test_signed_helper`
   - Notarize (credentials required): `op run --env-file=.env.release -- bundle exec rake dev:notarize_helper`
   - If the notarize task exits before stapling—even though Apple later accepts the submission—run `xcrun stapler staple libexec/macos/wifiwand-helper.app` yourself once `dev:notarization_status` reports `Accepted`
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
   op run --env-file=.env.release -- bundle exec rake dev:release_helper
   ```
   What it does:
   1. Builds the helper
   2. Signs with your Developer ID
   3. Tests the signed bundle
   4. Notarizes with Apple and staples the ticket

   **Without 1Password?**
   ```bash
   WIFIWAND_APPLE_DEV_ID="you@example.com" \
   WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
     bundle exec rake dev:release_helper
   ```

3. **Spot-check when needed**
   ```bash
   bundle exec rake dev:codesign_status
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
   - Check Apple’s queue: `bundle exec rake dev:notarization_history`
   - For a specific submission, run `bundle exec SUBMISSION_ID=<uuid> rake dev:notarization_status` (omit `SUBMISSION_ID` to automatically target the most recent submission). This command wraps `xcrun notarytool info`.
   - Pull the detailed log with `bundle exec SUBMISSION_ID=<uuid> rake dev:notarization_log` (same auto-detection applies)
   - If the submission was rejected, rebuild the helper (`bundle exec rake dev:build_signed_helper`) before re-running the release flow.

---

## Need More Detail?

- Background, troubleshooting, and the rationale for each requirement: `docs/dev/MACOS_CODE_SIGNING_CONTEXT.md`
- Rake task internals live alongside the tasks in `lib/wifi-wand/mac_helper_release.rb`.
- Forget the commands? Run `bundle exec rake dev:help` for a quick reminder of the common `op run` invocations.

Keeping this file short makes it easier to execute the release without rereading the entire history every time. Refer back to the context file whenever you need the “why.”
