# macOS Helper Permission Behavior

For this project, macOS permission is not intended to be tracked separately for each gem home or each gem
version.

## Runtime Install Location

`wifi-wand` installs the helper into a shared per-user directory:

`~/Library/Application Support/WifiWand/<gem-version>/wifiwand-helper.app`

That means:

- `mise` and `rbenv` do not each keep an independently registered helper inside their own gem homes at
  runtime.
- Both environments converge on the same user-level install area.
- If both environments use the same `wifi-wand` version, they target the same installed helper path.
- If they use different gem versions, they get different helper bundle paths under different version
  directories.

## What macOS Uses as Identity

The important identity is the helper's bundle metadata, especially the bundle identifier, not just the visible
app name.

In the helper's `Info.plist`, the project uses:

- `CFBundleName = wifiwand-helper`
- `CFBundleIdentifier = com.wifiwand.helper`

The permission-management docs also refer to the helper by that bundle identifier.

## Practical Behavior

The intended model is:

1. The first time the helper is run, macOS registers it and the user grants Location Services permission.
2. After that, the same gem version should not require more user intervention.
3. Upgrading to a new gem version should normally also continue to work without another permission grant,
   because the helper keeps the same bundle identifier and signing identity.

So:

- Same gem version after approval: no further action should normally be needed.
- New gem version: a new permission grant should normally not be needed.

## Important Caveat

macOS TCC and LaunchServices behavior can sometimes be sensitive to path, signature, or OS-version quirks. The
repo's docs acknowledge that macOS behavior is not perfectly uniform across releases.

Because of that, the correct statement is:

- The design goal is permission continuity across gem versions.
- If macOS prompts again after an upgrade, that would be an OS-level edge case, not the intended application
  model.

## Bottom Line

The helper is not meant to be "one separately authorized app per gem version." Multiple installed copies may
exist on disk, but they are intended to present as one logical macOS app identity for permission purposes via
the stable bundle identifier `com.wifiwand.helper`.
