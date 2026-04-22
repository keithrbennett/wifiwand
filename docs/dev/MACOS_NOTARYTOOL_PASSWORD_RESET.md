# Resetting macOS Notarization Credentials

Use this when the existing `notarytool` keychain profile needs to be refreshed, usually because the Apple
app-specific password was lost or rotated.

## Important Constraint

Apple app-specific passwords are view-once secrets. If you created one earlier but did not save it, Apple
will not show it again. The fix is to create a new app-specific password and store fresh `notarytool`
credentials.

## What Does Not Need to Be Redone

- Apple Team ID setup
- Developer ID certificate setup
- Bundle ID / helper registration
- `codesign` identity configuration

This is only a credential refresh for notarization.

## Step 1: Create a New App-Specific Password

1. Visit `https://appleid.apple.com`
2. Sign in with the Apple ID used for notarization
3. Open `Sign-In and Security`
4. Open `App-Specific Passwords`
5. Create a new password
6. Label it something like `wifi-wand notarization`
7. Copy it immediately

Apple will not show this password again later.

## Step 2: Store the Credentials Again

Preferred path:

```bash
bin/mac-helper public-info
bin/mac-helper store-credentials
```

If `WIFIWAND_APPLE_DEV_ID` is unset, the command prompts for the Apple ID email first. Then `notarytool`
prompts for the app-specific password interactively, so the password never appears in process argv.

Explicit email form:

```bash
WIFIWAND_APPLE_DEV_ID="you@example.com" bin/mac-helper store-credentials
```

Equivalent raw `notarytool` command:

```bash
xcrun notarytool store-credentials wifiwand-notarytool \
  --apple-id you@example.com \
  --team-id 97P9SZU9GG
```

## Expected Success Path

After you enter the app-specific password, `notarytool` should validate the credentials and store them in
the login keychain under the selected profile name.

You can then test the profile with:

```bash
bin/mac-helper history
```

## Current Blocker Seen On 2026-04-23

The current attempt failed with:

```text
Error: HTTP status code: 403. A required agreement is missing or has expired.
This request requires an in-effect agreement that has not been signed or has expired.
Ensure your team has signed the necessary legal agreements and that they are not expired.
```

This means the password entry itself was not the main problem. Apple rejected credential validation because
the developer account for Team ID `97P9SZU9GG` has at least one required agreement that is missing, expired,
or waiting for acceptance.

## Fixing the 403 Agreement Error

1. Sign in to the Apple Developer account for the team
2. Check for any legal agreements, license updates, or membership renewals that require acceptance
3. If applicable, check App Store Connect as well for account agreements that need an Account Holder or
   Admin to accept them
4. Confirm the Apple Developer Program membership is still active
5. Wait a few minutes for Apple's account state to propagate
6. After the agreement issue is resolved, rerun:

```bash
bin/mac-helper store-credentials
```

## Quick Sanity Check Commands

Show the current public configuration:

```bash
bin/mac-helper public-info
```

Retry storing credentials:

```bash
bin/mac-helper store-credentials
```

Test the profile after it stores successfully:

```bash
bin/mac-helper history
```
