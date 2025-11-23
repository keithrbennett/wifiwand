# wifiwand macOS Helper Assets

This directory contains the native macOS helper application that provides unredacted WiFi information on macOS 14 (Sonoma) and later.

## Contents

- `wifiwand-helper.app` - The signed and notarized helper bundle installed for end users
- `src/` - Swift source files compiled into the bundle

## Building

Run `bundle exec rake swift:compile` to rebuild the helper after editing the Swift source.

## Code Signing

For information on signing and notarizing the helper for release, see:
- [Code Signing Instructions](../../docs/dev/MACOS_CODE_SIGNING_INSTRUCTIONS.md)
- [Code Signing Context](../../docs/dev/MACOS_CODE_SIGNING_CONTEXT.md)
