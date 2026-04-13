# Testing Documentation for wifi-wand

This document describes how wifi-wand's test suite is organized and how to run the right scope for local development, CI, and native-host verification.

## Overview

The suite has three practical buckets:

- Default tests: mocked or otherwise hermetic tests. These are safe for CI and run by default.
- `:real_env_read_only`: tests that read the real host environment but do not intentionally mutate it.
- `:real_env_read_write`: tests that mutate the real host environment and therefore require capture/restore safeguards.

The `:real_env` tag is derived automatically whenever either `:real_env_read_only` or `:real_env_read_write` is present. That makes it easy for the harness to exclude all real-host tests by default.

## Quick Start

```bash
# Default safe suite
bundle exec rspec

# Include real-host read-only checks
WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec

# Include the full native-host suite, including read-write tests
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec
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

Real-host tests can additionally declare `real_env_os: :os_mac` or `real_env_os: :os_ubuntu`. The suite detects the current OS and skips foreign real-host examples automatically.

## Network Restore Behavior

Only `:real_env_read_write` tests participate in suite-level network capture and restoration.

Behavior:

- before the suite, the current network state is captured once
- after each `:real_env_read_write` example, the suite restores that state
- at suite end, the suite attempts a final restoration and raises if restoration fails

On macOS, examples tagged `:needs_sudo_access` refresh the sudo ticket immediately before the example instead of using a background keepalive thread.

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

## Related Files

- [spec/spec_helper.rb](/home/kbennett/code/wifiwand/primary/spec/spec_helper.rb)
- [spec/support/rspec_configuration.rb](/home/kbennett/code/wifiwand/primary/spec/support/rspec_configuration.rb)
- [spec/support/coverage_config.rb](/home/kbennett/code/wifiwand/primary/spec/support/coverage_config.rb)
- [docs/ENVIRONMENT_VARIABLES.md](/home/kbennett/code/wifiwand/primary/docs/ENVIRONMENT_VARIABLES.md)
