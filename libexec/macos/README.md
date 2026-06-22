# WifiWand macOS helper assets

- `wifiwand-helper.app` is the bundle installed for end users.
- `src/` contains the Swift sources compiled into the bundle.
- `wifiwand-helper.source-manifest.json` attests the committed helper source, entitlements, and bundle
  contents used to build the shipped helper.
- Run `bundle exec rake swift:compile_helper` or `bin/mac-helper-release build` after editing the Swift
  source, helper entitlements, or committed bundle template metadata.
  Both commands
  rebuild the signed bundle and refresh the source attestation manifest.
- Run `bundle exec rake swift:verify_helper_attestation` or `bin/mac-helper-release verify` when you only need
  to confirm the committed bundle still matches the source attestation manifest.
- Run `bundle exec rake swift:verify_helper` on macOS before release work when you need the aggregate
  attestation and code-signature verification.
  `bin/mac-helper-release` `test`, `notarize`, `release`, and `status` also fail fast when the committed
  bundle, manifest, helper source, and entitlements are out of sync, and the release/test/status paths verify
  the committed helper code signature.
