# wifiwand macOS helper assets

- `wifiwand-helper.app` is the bundle installed for end users.
- `src/` contains the Swift sources compiled into the bundle.
- `wifiwand-helper.source-manifest.json` attests which Swift source hash the committed bundle was built from.
- Run `bundle exec rake swift:compile` or `bin/mac-helper-release build` after editing the Swift source.
  Both commands
  rebuild the signed bundle and refresh the source attestation manifest.
- Run `bundle exec rake swift:verify_helper` or `bin/mac-helper-release verify` before release work.
  `bin/mac-helper-release` `test`, `notarize`, `release`, and `status` also fail fast when the committed
  bundle, manifest, and Swift source are out of sync.
