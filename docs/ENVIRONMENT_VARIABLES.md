# Environment Variables Reference

This document lists all environment variables that affect WifiWand behavior.

## Runtime Variables

### `WIFIWAND_OPTS`

Prepend default command-line switches from the environment, parsed with shell-style quoting so complex values
work just like they do in the shell. Use this for runtime defaults such as verbose output, UTC timestamps, or
machine-readable output formats.

To enable runtime verbose output by default, include the boolean value expected by the CLI:

```bash
export WIFIWAND_OPTS="--verbose true"
wifiwand info
```

The direct CLI equivalent is:

```bash
wifiwand -v true info
```

On Ubuntu, `connect` commands that include an inline password intentionally
show the exact password-bearing `nmcli` command. WifiWand targets
single-user machines under the operator's control, and preserving the exact
credential is considered more useful for troubleshooting than hiding it.
Avoid inline passwords on systems where local process inspection is not
trusted.

**Values:** Space-delimited options (e.g., `--output-format y`, `--verbose true`)

**Usage examples:**

```bash
export WIFIWAND_OPTS="--output-format y" # YAML
wifiwand info
```

```bash
export WIFIWAND_OPTS="--verbose true"
wifiwand status
```

```bash
export WIFIWAND_OPTS="--utc true"
wifiwand log
```

- **Overrides:** Later command-line arguments can override most defaults, but commands (e.g., `shell`) cannot
  be negated.
- **Scope:** `WIFIWAND_OPTS` can include invocation-wide defaults such as `--verbose true`, `--utc true`, or
  `--output-format y`. If a selected command does not use one of those defaults, WifiWand ignores it for that
  command. Command-specific options are still validated against the selected command: `--interval 10` is valid
  when the invocation runs `log`, but invalid when it runs `info`. Unknown options always abort with a
  configuration error.
- **Parsing errors:** If the value contains unmatched quotes or otherwise cannot be parsed, WifiWand aborts
  with a configuration error.

### `WIFIWAND_DISABLE_MAC_HELPER`

Disable the macOS helper application for permission-sensitive WiFi reads. This is mainly useful for
troubleshooting or for deliberately accepting macOS-redacted SSID behavior.

**Values:**
- `1`, `true`, `yes`, or `on` - Disable the helper.
- unset, `0`, `false`, `no`, `off`, or any other value - Use the helper when it is supported and
  available.

**Usage:**
```bash
WIFIWAND_DISABLE_MAC_HELPER=1 wifiwand info
```

## Test Configuration Variables

### `WIFIWAND_VERBOSE`

Enable verbose output in the test support code. Test helpers accept the usual truthy values (`true`,
`yes`, `on`, or `1`). Other values are treated as disabled.

**Values:** `true`, `yes`, `on`, or `1` to enable

**Usage:**

```bash
WIFIWAND_VERBOSE=true bundle exec rspec
WIFIWAND_VERBOSE=yes bundle exec rake test:read_only
WIFIWAND_VERBOSE=true bundle exec rake test:all
```

### `WIFIWAND_REAL_ENV_TESTS`

Control whether tests that touch the real host environment run.

**Values:**
- `none` or unset (default) - Run only ordinary mocked/hermetic tests
- `read_only` - Also run tests tagged `:real_env_read_only`
- `all` - Run both `:real_env_read_only` and `:real_env_read_write`

**Usage:**
```bash
# Default: safe tests only
bundle exec rspec

# Run real-host read-only tests too
WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec

# Run all real-host tests, including mutating ones
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec
```

If you use the corresponding targeted Rake tasks, quote the full `task[arg]` expression for portability:

```bash
bundle exec rake 'test:read_only_target[./spec/wifi_wand/platforms/mac/model_spec.rb]'
bundle exec rake 'test:real[./spec/wifi_wand/platforms/mac/model_spec.rb]'
```

Why this matters:

- In `bash`, the quotes are optional.
- In `zsh`, the quotes are required because brackets are treated as glob syntax.
- Quoting is still the safer cross-shell habit.

**⚠️ WARNING:** Never use `read_only` or `all` in CI environments. Real-environment tests depend on host
hardware and machine state. `all` additionally runs host-mutating tests.

### `RSPEC_RUNNING`

Automatically set by RSpec when tests are running. Adjusts timeout values for better test performance.

**Values:** Set to `true` by the test framework

**Usage:** Internal use only - do not set manually.

### `WIFIWAND_COBERTURA_COVERAGE`

Control whether the test coverage setup loads `simplecov-cobertura` and registers the Cobertura XML
formatter.

**Values:**
- unset, `true`, `yes`, `on`, or `1` - Generate Cobertura XML coverage output
- `false`, `no`, `off`, or `0` - Skip loading `simplecov-cobertura` and skip Cobertura XML output

**Usage:**
```bash
WIFIWAND_COBERTURA_COVERAGE=false bundle exec rspec
```

This flag affects runtime formatter loading only. `Gemfile` still declares `simplecov-cobertura` as a
development/test dependency, so Bundler must still resolve it before the suite can start. To test against a
SimpleCov version that is incompatible with `simplecov-cobertura`, modify `Gemfile` as well, then refresh the
bundle.

## Coverage Resultset Files

SimpleCov chooses the resultset filename from `WIFIWAND_REAL_ENV_TESTS`.
Branch coverage is enabled by default.

**Behavior:**
- Unset or `none` - Write coverage to `coverage/.resultset.json`
- `read_only` - Write coverage to `coverage/.resultset.<os>.json`
- `all` - Write coverage to `coverage/.resultset.<os>.json`

**Usage:**
```bash
# Default safe-suite artifact
bundle exec rspec

# Real-environment artifact for the current OS
WIFIWAND_REAL_ENV_TESTS=read_only bundle exec rspec
WIFIWAND_REAL_ENV_TESTS=all bundle exec rspec
```

`<os>` resolves to `mac` on macOS and `ubuntu` on Linux.

**Important:** the filename only tells you which test scope wrote the file; it does not guarantee that the run
was unfiltered or current.

- A filtered or partial run still writes one of the filenames above.
- A resultset becomes stale after relevant source files change.
- For whole-codebase coverage analysis, developers should first run a fresh unfiltered suite, then inspect the
  resulting file and verify tracked runtime files with cov-loupe.

## CI/CD Guidelines

**Default behavior is CI-safe:** When `WIFIWAND_REAL_ENV_TESTS` is unset, only safe, mocked/hermetic tests
run.

**Never set these in CI:**
- `WIFIWAND_REAL_ENV_TESTS=read_only`
- `WIFIWAND_REAL_ENV_TESTS=all`

**Why?**
- CI runners typically lack WiFi hardware
- Even read-only real-host tests depend on runner-specific state
- Modifying network state disrupts the CI server
- CI may not be running a supported OS (macOS or Ubuntu)

See [Testing Documentation](../dev/docs/TESTING.md) for more details.
