# wifi-unredactor Research

## Problem Background
- Starting with macOS Sonoma, Apple redacts SSID/BSSID details returned by command-line tools unless the
  binary holds Location Services entitlement.
- wifiwand's macOS model currently gathers SSIDs via `system_profiler` and related CLI utilities, so it
  inherits the redaction.
- The user experience regresses: scans show `<redacted>` names even when the device is connected or the
  network is visible.

## How wifi-unredactor avoids redaction
1. Minimal Cocoa app bundle (`wifi-unredactor.app`) is distributed with the Swift source inside the bundle
   (`Contents/MacOS/wifi-unredactor.swift`) and a build script.
2. On launch the app creates a `CLLocationManager`, requests "always" authorization, and waits for
   authorization callbacks.
3. Once authorized, it calls `CWWiFiClient.shared().interface()` to access CoreWLAN APIs directly and reads
   `ssid()` and `bssid()` from the active interface. Results are emitted as pretty-printed JSON and the app
   immediately terminates. If authorization is denied, a JSON error is printed and the app exits.
4. `Info.plist` declares `NSLocationAlwaysUsageDescription` and sets `LSUIElement` to true so no dock icon
   appears, making it acceptable as a helper invoked from CLI.
5. A thin wrapper script (`build-and-install.sh`) compiles the Swift file with `swiftc` linking Cocoa,
   CoreLocation, and CoreWLAN frameworks, then copies the bundle to `~/Applications`. Running the app once via
   Finder triggers the Location Services prompt, after which it can run headlessly from the CLI.

Effectively, wifi-unredactor sidesteps Apple's privacy guard by:
- Packaging a GUI bundle able to show the Location Services consent dialog, something CLI binaries are barred
  from doing.
- Using CoreWLAN directly after consent, which returns the true SSID/BSSID instead of `<redacted>`.
- Returning data via JSON so scripts can consume it.

## Strategy for wifiwand

**Goals**
- Restore access to actual SSID names in scans and status readouts on macOS Sonoma+.
- Minimise disruption to existing CLI workflows and avoid shipping precompiled binaries if possible.

**Recommended approach**
1. **Bundle a Swift helper similar to wifi-unredactor.**
   - Embed a small app bundle (or compile on-demand) inside the gem under `resources/macos`.
   - Reuse the same pattern: `NSApplication` + `CLLocationManager` + `CWWiFiClient` returning JSON to stdout.
   - Update the bundle identifier and location usage string to reference wifiwand.

2. **Provide an onboarding command to grant permissions.**
   - Add `wifiwand mac authorize-wifi` (name TBD) that opens the helper bundle with `open`.
   - Guide the user through System Settings > Privacy & Security > Location Services if they dismiss the
     prompt.
   - Store a flag once permission is confirmed (e.g., `~/Library/Application
     Support/WifiWand/permissions.json`) to avoid nagging.

3. **Leverage the helper for SSID lookups.**
   - When fetching the current SSID or scanning, call the helper executable (`.../Contents/MacOS/...`) and
     parse the JSON response.
   - Detect error cases (`location services denied`, helper missing, non-zero exit) and gracefully fall back
     to the current `system_profiler` pipeline so the tool still works, albeit redacted.
   - Cache successful responses for the duration of the command invocation to avoid repeated helper launches.

4. **Handle installation and updates.**
   - During gem install or first `wifiwand` invocation on macOS, check whether the helper executable exists
     and matches the current version.
   - If the Xcode Command Line Tools (swiftc) are missing, ship a prebuilt binary for the common architectures
     (arm64/x86_64) or prompt the user to install CLT before building.

5. **Document the privacy implications.**
   - Update README/docs to explain why Location Services is required, what data is read, and how to revoke
     access.
   - Provide troubleshooting steps mirroring wifi-unredactor (e.g., re-open the helper if the app disappears
     from Location Services).

**Technical integration details**
- Add a Ruby wrapper in `MacOsModel` that shells out to the helper first; only if it fails fall back to the
  existing `system_profiler` based implementation.
- Ensure spawn uses `Open3.capture3` so stdout/stderr/exitstatus can be inspected.
- Validate that the helper is executed with the same user context (Location Services permissions are
  per-user).
- Consider gating the helper invocation to macOS 14+ by checking `macos_version` to avoid unnecessary prompts
  on Ventura and earlier.


## Implementation Outline

1. **Helper bundle packaging**
   - Place `wifiwand-helper.app` under `libexec/macos/<version>/` inside the gem.
   - Include Swift source (similar to wifi-unredactor) plus a small build script for contributors.
   - During gem install/first run, copy the bundle to `~/Library/Application
     Support/WifiWand/<helper_version>/` with the correct permissions.

2. **Ruby integration layer**
   - Add `WifiWand::MacOsHelper` module responsible for:
     - Locating the installed helper.
     - Running it via `Open3.capture3`.
     - Parsing the JSON response (`interface`, `ssid`, `bssid`, optional error).
     - Detecting authorization errors and surfacing actionable messages.
   - Update `WifiWand::MacOsModel#_connected_network_name`, `#scan_networks`, etc., to call the helper first
     and fall back to existing CLI-based approaches.

3. **Permission onboarding**
   - New CLI command `wifiwand mac authorize` that runs `open <helper bundle>` to trigger the Location
     Services prompt and prints step-by-step guidance.
   - Helper returns a specific JSON error (`{"error":"location services denied"}`) so we can prompt the user
     to rerun the authorize command.

4. **Configuration & fallbacks**
   - Add `WifiWand.config.use_helper = true/false` so CI or restricted environments can disable helper usage.
   - Log warnings when falling back to redacted data, with instructions on enabling the helper.

5. **Version management**
   - Store the installed helper version (e.g., `~/.wifiwand/helper_version`) and reinstall when the gem
     version changes.
   - Keep the bundle identifier stable across releases to avoid repeated permission prompts unless significant
     changes require a new ID.

6. **Testing hooks**
   - Provide an environment override (`WIFIWAND_HELPER_CMD`) so specs can substitute a fake JSON-emitting
     script.
   - Unit tests cover successful responses, denied permissions, missing helper, and fallback paths.

## Additional considerations
- **Code signing / notarization:** If distributing a compiled helper inside the gem, signing it with an Apple
  developer ID will reduce Gatekeeper friction. Otherwise, expect a right-click > Open workflow.
- **Testing:** Add integration tests that mock the helper JSON response to verify parsing logic without
  requiring macOS APIs in CI.
- **Fallback plan:** Document manual alternatives (e.g., `open /System/Library/CoreServices/Wireless
  Diagnostics.app`) for users unwilling to grant location access.
- **Maintenance:** Track upstream changes; if Apple extends the privacy requirement to CoreWLAN APIs, the
  helper may need to adopt entitlement-based approaches or use the Network Extension framework.
