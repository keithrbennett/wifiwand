# Testing Documentation for wifi-wand

This document describes how wifi-wand's test suite is organized and how to run the right scope for local
development, CI, and native-host verification.

## Overview

The suite has three practical buckets:

- Default tests: mocked or otherwise hermetic tests. These are safe for CI and run by default.
- `:real_env_read_only`: tests that read the real host environment but do not intentionally mutate it.
- `:real_env_read_write`: tests that mutate the real host environment and therefore require capture/restore
  safeguards.

The `:real_env` tag is derived automatically whenever either `:real_env_read_only` or `:real_env_read_write`
is present. That makes it easy for the harness to exclude all real-host tests by default.

## Quick Start

```bash
# Default safe suite
bundle exec rspec

# Include real-host read-only checks
WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec

# Include the full native-host suite, including read-write tests
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec
```

## Fail-Fast And Verbose Debugging

When debugging real-environment failures, it is often best to stop on the first failure and print the
underlying OS commands.

Use fail-fast directly with RSpec:

```bash
# Stop on the first failure in the full real-host suite
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec --fail-fast

# Equivalent explicit one-failure form
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec --fail-fast=1
```

If you prefer the Rake wrappers, pass fail-fast through `RSPEC_OPTS`:

```bash
RSPEC_OPTS="--fail-fast" bundle exec rake test:all
```

To print the underlying OS commands while the suite runs:

```bash
WIFIWAND_REAL_ENV_TESTS=all WIFIWAND_VERBOSE=true bundle exec rspec --fail-fast
```

Or with the Rake wrapper:

```bash
WIFIWAND_VERBOSE=true RSPEC_OPTS="--fail-fast" bundle exec rake test:all
```

For narrower debugging, combine these with a single spec file:

```bash
WIFIWAND_REAL_ENV_TESTS=all WIFIWAND_VERBOSE=true bundle exec rspec \
  spec/wifi-wand/models/mac_os_model_spec.rb --fail-fast
```

## Targeted Rake Tasks

Use the Rake tasks when you want the convenience of scope selection plus a specific spec file or files.

Examples:

```bash
# Read-only real-host tests for one file
bundle exec rake 'test:read_only_target[./spec/wifi-wand/models/mac_os_model_spec.rb]'

# Full real-host tests for one file
bundle exec rake 'test:real[./spec/wifi-wand/models/mac_os_model_spec.rb]'

# Multiple targets are passed through to RSpec
bundle exec rake 'test:real[./spec/a_spec.rb ./spec/b_spec.rb]'
```

Shell behavior matters here:

- In `bash`, the quotes are optional.
- In `zsh`, the quotes are required because `[` and `]` are treated as glob syntax.
- Preferred cross-shell form: `bundle exec rake 'test:real[./spec/path_spec.rb]'`
- `zsh` alternatives: escape the brackets or prefix with `noglob`

Examples for `zsh`:

```bash
bundle exec rake test:real\[./spec/wifi-wand/models/mac_os_model_spec.rb\]
noglob bundle exec rake test:real[./spec/wifi-wand/models/mac_os_model_spec.rb]
```

## CI Guidance

CI should run only the default suite.

Do not enable `WIFIWAND_REAL_ENV_TESTS` in CI:

- CI runners often lack WiFi hardware.
- Even read-only real-host tests depend on machine-specific state.
- Read-write real-host tests can disrupt connectivity and require restoration.

## Tag Model

### `:real_env_read_only`

Use this for tests that touch the real machine but only read from it.

Examples:

- detect the WiFi interface
- read IP address or nameservers
- read macOS version from the host
- scan networks when WiFi is already on

These tests are not suitable for CI, but they do not need the suite-level restore harness.

### `:real_env_read_write`

Use this for tests that intentionally change real machine state.

Examples:

- turn WiFi on or off
- disconnect from the current network
- connect to a network
- change nameservers

These tests trigger the suite's real-host restoration flow.

### `:real_env`

This tag is derived automatically from the two tags above. Do not set it manually.

It is used for:

- excluding all real-host tests by default
- OS-specific gating for real-host examples
- deciding whether macOS auth preflight should run

## OS Gating

Mocked tests run on any supported host.

Real-host tests can additionally declare `real_env_os: :os_mac` or `real_env_os: :os_ubuntu`. The suite
detects the current OS and skips foreign real-host examples automatically.

## Network Restore Behavior

Only `:real_env_read_write` tests participate in suite-level network capture and restoration.

Behavior:

- before the suite, the current network state is captured once
- after each `:real_env_read_write` example, the suite restores that state
- at suite end, the suite attempts a final restoration and raises if restoration fails

On macOS, examples tagged `:needs_sudo_access` refresh the sudo ticket immediately before the example instead
of using a background keepalive thread.

### Recommended Real-Host Coverage

When validating `:real_env_read_write` behavior locally, test both of these network types when possible:

- an open network that does not require a password
- a password-protected network that requires stored or interactive credentials

Both cases matter. Open networks exercise disconnect/reconnect behavior without keychain-backed password
lookup, while password-protected networks exercise saved-password capture, restore-time reconnects, and
macOS authentication/keychain edge cases. A change that passes on one type can still fail on the other.

If macOS redacts the current SSID during preflight and the suite aborts because it cannot capture a
restorable network name, provide the restore target explicitly:

```bash
WIFIWAND_RESTORE_NETWORK_NAME="Your SSID" WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec
```

Use this only when you are certain of the currently connected network name. The override is intended for
real-host debugging on macOS systems that expose the current network as `<redacted>`.

## Coverage Artifacts

Two resultset filenames are used depending on whether the run touches the real host:

- `coverage/.resultset.json`
  This is used for ordinary runs, including the default safe suite.

- `coverage/.resultset.<os>.json`
  This is used for any real-environment run, including both:
  `WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec`
  and
  `WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec`

The OS suffix appears only for real-environment runs so those host-dependent artifacts
do not overwrite the default mocked/hermetic resultset.

### Interpreting Coverage Correctly

Coverage artifacts are only authoritative for the exact test run that generated them.

- If you run a filtered test subset, the resultset reflects that subset only.
- If source files change after the resultset is written, coverage tools may report stale entries such as
  `length_mismatch`.
- Developers and agents must not treat an existing coverage file as proof of whole-codebase coverage unless
  they intentionally ran a fresh unfiltered suite for that purpose.

Practical rule:

- For codebase-wide review or planning, first run a fresh unfiltered suite such as `bundle exec rspec` or
  `bundle exec rake test:safe`, then inspect the newly generated resultset.
- For targeted local work, it is fine to rely on targeted coverage artifacts, but only for the code exercised
  by that run.

This is an operator responsibility, not an automatic guarantee provided by the resultset filenames.

## Modifier Env Vars

These env vars are orthogonal to test scope and can be combined with any rake task or rspec invocation:

```bash
# Show underlying OS commands during tests
WIFIWAND_VERBOSE=true bundle exec rake test:read_only

# Enable branch coverage analysis
COVERAGE_BRANCH=true bundle exec rake test:safe
```

## Writing Tests

Use the smallest scope that matches reality:

```ruby
# Default mocked/hermetic test
it 'returns wifi status' do
  expect(subject.wifi_on?).to be(true).or(be(false))
end

# Real-host read-only test
it 'reads the current IP address', :real_env_read_only, real_env_os: :os_ubuntu do
  expect(subject.ip_address).to match(/^\d+\.\d+\.\d+\.\d+$/)
end

# Real-host read-write test
it 'disconnects from the current network', :real_env_read_write do
  expect { subject.disconnect }.not_to raise_error
end
```

Guidelines:

- Prefer mocked tests whenever behavior can be exercised without the host.
- Use `:real_env_read_only` for host-dependent checks that must stay read-only.
- Use `:real_env_read_write` only for the small set of tests that truly need mutation.
- Add `real_env_os:` when a real-host test only makes sense on one OS.

## Why `#disconnect` Has No Real-Environment Test

`BaseModel#disconnect` is fully covered by mocked unit tests that exercise every
code path: the `till(:disassociated)` timeout, the `disassociated_stable?` window,
and the `NetworkDisconnectionError` construction.

A real-environment test was written and investigated but ultimately removed for the
following reason.

### What we tried

A real-env read-write test called `'either disassociates or surfaces a verified
disconnect failure'` called `subject.disconnect` and accepted two outcomes:

1. Disconnect succeeded → assert `associated?` is `false`.
2. `NetworkDisconnectionError` raised → assert `associated?` is still `true` and
   the error reason matched the expected pattern.

### Why it cannot work reliably on macOS

macOS's `airportd` daemon monitors preferred-network associations and starts an
auto-reconnect cycle within milliseconds of any programmatic disassociation
(including a CoreWLAN `disassociate()` call). This means:

- The test always lands in the `NetworkDisconnectionError` branch — `airportd`
  reconnects faster than our stability check can confirm disassociation.
- The test never exercises the "clean disconnect succeeded" branch.
- The restore phase after the test fights the same reconnect cycle, causing
  spurious `-3900 tmpErr` errors from `networksetup`.

### Alternatives considered

| Approach | Problem |
|---|---|
| Remove network from preferred list before disconnecting | macOS reconnects to another preferred network instead |
| Turn WiFi off | Tests a different operation (`wifi_off`), not `disconnect` |
| Private `airportd` API to suppress reconnect | Not accessible without private frameworks |
| Increase stability window / retry count | Only delays the inevitable; macOS always wins the race |

### Conclusion

Programmatic disassociation on macOS is inherently non-deterministic in the
presence of preferred networks. The disconnect logic is correct and well-covered
by mocked tests. Adding a real-environment test would only test macOS's
auto-reconnect behavior, not our code.

## Related Files

- [spec/spec_helper.rb](../spec/spec_helper.rb)
- [spec/support/rspec_configuration.rb](../spec/support/rspec_configuration.rb)
- [spec/support/coverage_config.rb](../spec/support/coverage_config.rb)
- [docs/ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md)
