# Environment Variables Reference

This document lists all environment variables that affect wifi-wand behavior.

## Runtime Variables

### `WIFIWAND_VERBOSE`

Enable verbose output showing underlying OS commands and their output.

**Values:** Any non-empty value enables verbose mode (e.g., `true`, `1`, `yes`)

**Usage:**
```bash
WIFIWAND_VERBOSE=true wifi-wand info
```

**Alternative:** Use the `-v` command-line flag instead:
```bash
wifi-wand -v info
```

### `WIFIWAND_OPTS`
Prepend default command-line switches from the environment, parsed with shell-style quoting so complex values work just like they do in the shell.
**Values:** Space-delimited options (e.g., `--output_format y`, `--verbose`)
**Usage examples:**
```bash
export WIFIWAND_OPTS="--output_format y" # YAML
wifi-wand info
```

```bash
export WIFIWAND_OPTS="--verbose"
wifi-wand status
```
- **Overrides:** Later command-line arguments can override most defaults, but subcommands (e.g., `shell`) cannot be negated, nor can their options be overridden from the environment.
- **Scope:** `WIFIWAND_OPTS` only supports top-level flags; subcommand options (like `log --file`) must still be passed on the command line when you invoke the subcommand.
- **Parsing errors:** If the value contains unmatched quotes or otherwise cannot be parsed, wifi-wand aborts with a configuration error.

## Test Configuration Variables

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

**⚠️ WARNING:** Never use `read_only` or `all` in CI environments. Real-environment tests depend on host hardware and machine state. `all` additionally runs host-mutating tests.

### `RSPEC_RUNNING`

Automatically set by RSpec when tests are running. Adjusts timeout values for better test performance.

**Values:** Set to `true` by the test framework

**Usage:** Internal use only - do not set manually.

## Coverage Variables

### `COVERAGE_BRANCH`

Enable SimpleCov branch coverage analysis.

**Values:** `true` to enable

**Usage:**
```bash
COVERAGE_BRANCH=true bundle exec rspec
```

**Note:** Branch coverage is more detailed but slower than line coverage. Use for thorough analysis before commits or releases.

### `WIFIWAND_COVERAGE_MODE`

Select which SimpleCov resultset filename is authoritative for the current run.

**Values:**
- `default` or unset - Write coverage to `coverage/.resultset.json`
- `native_all` - Write coverage to `coverage/.resultset.json.<os>.all`

**Usage:**
```bash
# Default safe-suite artifact
bundle exec rspec

# Native full-suite artifact for MCP/cov-loupe review
WIFIWAND_COVERAGE_MODE=native_all \
  WIFIWAND_REAL_ENV_TESTS=all \
  bundle exec rspec
```

**Validation:** `native_all` is accepted only when the full native suite is being run (`WIFIWAND_REAL_ENV_TESTS=all`). This prevents partial or stale `.ubuntu.all` / `.mac.all` artifacts from being treated as authoritative.

## CI/CD Guidelines

**Default behavior is CI-safe:** When `WIFIWAND_REAL_ENV_TESTS` is unset, only safe, mocked/hermetic tests run.

**Never set these in CI:**
- `WIFIWAND_REAL_ENV_TESTS=read_only`
- `WIFIWAND_REAL_ENV_TESTS=all`

**Why?**
- CI runners typically lack WiFi hardware
- Even read-only real-host tests depend on runner-specific state
- Modifying network state disrupts the CI server
- CI may not be running a supported OS (macOS or Ubuntu)

See [Testing Documentation](TESTING.md) for more details.
