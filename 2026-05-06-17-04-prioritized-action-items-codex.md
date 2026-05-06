Most recent git commit at review start: `293cad3 (HEAD -> main, origin/main, origin/HEAD,
gitlab/main, gitlab/HEAD, bitbucket/main, bitbucket/HEAD) Narrow broad exception handling`.

Review scope was limited to git-tracked files. `git status --short` was clean at review start.

Notes:

- Consulted `dev/prompts/guidelines/ai-code-evaluator-guidelines.md` and
  `dev/prompts/guidelines/issues-reviewed-and-dismissed.md`; issues already dismissed there are not repeated.
- The requested `docs/dev/arch-decisions` path is not present as a tracked directory. I consulted
  `dev/docs/architecture/changes/macos-redacted-network-names-policy.md`, the tracked architecture note
  relevant to the macOS findings.
- Used the `cov-loupe` MCP server. After `bundle exec rspec`, the safe suite reported 1,939 examples,
  0 failures, and line coverage of 94.15%.

---

## Issue 1: macOS Helper Attestation Is Stale

### Description

The committed macOS helper source attestation no longer matches the committed helper source or helper bundle.
Running the tracked release verification path fails:

```text
bundle exec ruby -Ilib -e "require 'wifi-wand/mac_helper/mac_helper_release'; WifiWand::MacHelperRelease.verify_source_attestation!"
```

The verification aborts with:

```text
Source attestation failed:
Shipped macOS helper bundle is out of sync with the committed helper source, entitlements, or bundle contents
```

The tracked manifest says the Swift source SHA is
`ef2223545ab488df34ec45a4bf119a9fb8888e3c79576150f094d8e47e812399`, but the tracked
`libexec/macos/src/wifiwand-helper.swift` currently hashes to
`c602c8e9bb4c38c31ca83256bd9725c20855701c504d72363e42fb6d280c5a25`. The tracked bundle fingerprint also
differs from the manifest.

This is a release integrity problem because the gem ships the compiled helper bundle while excluding the
helper Swift source and attestation manifest from the packaged gem.

### Assessment

- **Severity:** High
- **Effort to Fix:** Medium
- **Impact if Unaddressed:** A release can ship a notarized macOS helper binary that cannot be traced back to
  the committed source attestation, undermining auditability and macOS helper trust.

### Strategy

On macOS with the intended signing identity, rebuild the helper bundle from the tracked Swift source and
refresh `libexec/macos/wifiwand-helper.source-manifest.json`. If the current binary is the intended artifact
instead, revert or update the Swift source so source, bundle, and manifest describe the same artifact.
Verify with `bundle exec rake swift:verify_helper` before staging any release.

### Actionable Prompt

```text
Fix the stale macOS helper source attestation.

Investigate the mismatch among:
- libexec/macos/src/wifiwand-helper.swift
- libexec/macos/wifiwand-helper.app
- libexec/macos/wifiwand-helper.source-manifest.json

Choose the correct source of truth. If the tracked Swift source is correct, rebuild the helper on macOS with
the configured signing identity using the existing helper build workflow, refresh the source manifest, and
verify the bundle. If the tracked helper bundle is correct, update or revert the Swift source and manifest so
the attestation is truthful.

Do not bypass the existing attestation check. The final state must pass:

bundle exec rake swift:verify_helper

Also run the smallest relevant specs for the helper build/release paths.

After completing the fix, propose a detailed commit message. Focus on why
the approach was chosen and any non-obvious decisions or tradeoffs.
Describe what the tests verify in terms of expected behavior, not the
mechanics of how they were written. Omit restatements of what the diff
already shows.
```

---

## Issue 2: CI Does Not Enforce Helper Attestation

### Description

The safe test suite passes even while the helper attestation is stale. `.github/workflows/test.yml` only runs
`bundle exec rspec`, and the actual attestation task in `lib/tasks/swift.rake` is not part of CI. The specs
exercise the behavior with mocks and temporary fixtures, but they do not prove that the committed helper
bundle, source, entitlements, and manifest match in the current checkout.

This gap allowed Issue 1 to exist on `main` without a failing automated check.

### Assessment

- **Severity:** High
- **Effort to Fix:** Low
- **Impact if Unaddressed:** Future helper source/binary drift can continue to merge unnoticed, creating
  repeat release-blocking or release-integrity failures.

### Strategy

Add `bundle exec rake swift:verify_helper` to CI. The verification is hash- and file-based and does not
require compiling Swift, so it can run on an Ubuntu job. Keep the compile task macOS-only, but make the
attestation verification a normal required check.

### Actionable Prompt

```text
Add a CI gate that verifies the committed macOS helper bundle attestation.

Update .github/workflows/test.yml so CI runs:

bundle exec rake swift:verify_helper

Use the existing Rake task rather than reimplementing the check in the workflow. The check should run in a
normal CI job and fail when libexec/macos/wifiwand-helper.source-manifest.json does not match the tracked
Swift source, entitlements, and helper bundle.

Add or update documentation only if needed to clarify that CI verifies helper attestation but does not compile
or sign the helper. Run the workflow-equivalent local command and the smallest relevant specs for Swift/helper
tasks.

After completing the fix, propose a detailed commit message. Focus on why
the approach was chosen and any non-obvious decisions or tradeoffs.
Describe what the tests verify in terms of expected behavior, not the
mechanics of how they were written. Omit restatements of what the diff
already shows.
```

---

## Issue 3: macOS Redaction Paths Can Still Look Authoritative

### Description

The macOS architecture note requires identity-sensitive commands to avoid pretending that redacted or
unverifiable SSID data is authoritative. The current available-network path still has a misleading case:

- `MacOsModel#helper_available_network_names` returns `nil` when the helper reports
  `location_services_blocked?`.
- `MacOsModel#_available_network_names` then falls through to `airport` and `system_profiler` fallback
  sources.
- `CommandOutputSupport#available_networks_empty_message` warns only when the final scan result is empty.

If a fallback returns a non-empty but incomplete list, `wifi-wand avail_nets` prints it as ordinary available
network output, without indicating that the trusted helper path was blocked by Location Services. The existing
spec `falls back to system_profiler when helper is blocked by Location Services` locks in that behavior.

A related `info` ambiguity remains in `BaseModel#wifi_info`: redaction errors from `connected_network_name`
are rescued into `'network' => nil`, so `info` can show a nil network without saying whether WiFi is
disconnected, associated with unavailable SSID identity, or blocked by macOS privacy.

### Assessment

- **Severity:** Medium
- **Effort to Fix:** Medium
- **Impact if Unaddressed:** Users and scripts can treat incomplete macOS SSID data as authoritative,
  especially on macOS 14+ when Location Services blocks the helper.

### Strategy

Separate "no visible networks" from "network names are unavailable or untrusted." For human output, emit a
clear warning or targeted error when the helper reports Location Services blocking. For machine-readable
output, expose a status field or structured result so callers can distinguish successful scans from degraded
fallbacks. For `info`, include generic association and SSID-identity availability instead of collapsing
redaction into a plain nil network.

### Actionable Prompt

```text
Make macOS redaction/degraded SSID data explicit in available-network and info output.

Start by reviewing:
- dev/docs/architecture/changes/macos-redacted-network-names-policy.md
- lib/wifi-wand/models/mac_os_model.rb
- lib/wifi-wand/command_line_interface/command_output_support.rb
- lib/wifi-wand/models/base_model.rb
- spec/wifi-wand/models/mac_os_model_spec.rb
- spec/wifi-wand/commands/avail_nets_command_spec.rb

Update the macOS available-network path so a Location Services block from the helper is not silently converted
into ordinary-looking fallback scan output. Preserve useful fallback data if appropriate, but make the
degraded status visible in human output and machine-readable output.

Also update info output so a redacted current SSID is distinguishable from "not connected"; include enough
state for users and scripts to see that WiFi may be associated while exact SSID identity is unavailable.

Add focused specs for a helper Location Services block with non-empty fallback scan data, empty fallback data,
and info output under macOS SSID redaction.

After completing the fix, propose a detailed commit message. Focus on why
the approach was chosen and any non-obvious decisions or tradeoffs.
Describe what the tests verify in terms of expected behavior, not the
mechanics of how they were written. Omit restatements of what the diff
already shows.
```

---

## Issue 4: Ubuntu `nmcli` Parsing Mishandles Backslash Escapes

### Description

`UbuntuModel#nmcli_split` is intended to parse `nmcli -t` output. The local `nmcli` man page states that terse
mode escapes both `:` and `\` characters using backslash. The current parser only splits on a colon not
immediately preceded by a backslash, then only unescapes `\:`.

That misses two real cases:

- literal backslashes remain double-escaped, so an SSID or profile containing `\` will not compare equal to
  the real SSID
- separators after an escaped literal backslash can be misclassified because the regex does not account for
  even versus odd runs of backslashes

This parser feeds preferred-network lookup, active profile lookup, saved password resolution, available
network names, security lookup, and DNS operations.

### Assessment

- **Severity:** Medium
- **Effort to Fix:** Low
- **Impact if Unaddressed:** Ubuntu users with SSIDs or NetworkManager profile names containing literal
  backslashes can see failed saved-password lookup, incorrect profile matching, failed removal, or wrong DNS
  target selection.

### Strategy

Replace the regex/gsub parser with a small character parser that honors `nmcli` terse escaping rules:
split only on unescaped field separators, unescape both `\:` and `\\`, and preserve unknown escape sequences
predictably. Add tests for colons, backslashes, field separators after escaped backslashes, and profile/SSID
matching through the existing public helpers.

### Actionable Prompt

```text
Fix Ubuntu nmcli terse-output parsing for backslash escapes.

Update UbuntuModel#nmcli_split in lib/wifi-wand/models/ubuntu_model.rb so it implements nmcli terse escaping
for both literal colons and literal backslashes. The parser should split on real field separators, unescape
\: to : and \\ to \, and handle separators following an escaped literal backslash correctly.

Add focused specs in spec/wifi-wand/models/ubuntu_model_spec.rb for:
- an SSID containing a literal backslash
- a profile name containing a literal backslash
- a field ending with a literal backslash before the separator
- existing colon-containing SSID behavior, to prevent regressions

Also add at least one higher-level spec showing that saved profile matching or active profile parsing works
for a backslash-containing value.

After completing the fix, propose a detailed commit message. Focus on why
the approach was chosen and any non-obvious decisions or tradeoffs.
Describe what the tests verify in terms of expected behavior, not the
mechanics of how they were written. Omit restatements of what the diff
already shows.
```

---

## Summary Table

| Brief Description (<= 50 chars) | Severity (H/M/L) | Effort (H/M/L) | Impact if Unaddressed | Link to Detail |
| :--- | :---: | :---: | :--- | :--- |
| Helper attestation is stale | H | M | Ships unauditable macOS helper binary/source state. | [See detail](#issue-1-macos-helper-attestation-is-stale) |
| CI misses helper attestation | H | L | Same release-integrity drift can recur unnoticed. | [See detail](#issue-2-ci-does-not-enforce-helper-attestation) |
| Redacted macOS scans look authoritative | M | M | Users/scripts can trust incomplete SSID data. | [See detail](#issue-3-macos-redaction-paths-can-still-look-authoritative) |
| Ubuntu nmcli backslashes misparse | M | L | Backslash SSIDs/profiles can break matching and DNS targeting. | [See detail](#issue-4-ubuntu-nmcli-parsing-mishandles-backslash-escapes) |
