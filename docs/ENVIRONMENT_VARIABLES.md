# Environment Variables Reference

This document lists all environment variables that affect wifi-wand behavior.

## Runtime Variables

### `WIFIWAND_VERBOSE`

Enable verbose output showing underlying OS commands and their output.

**Values:** Any non-empty value enables verbose mode (e.g., `true`, `1`, `yes`)

**Usage:**
```bash
WIFIWAND_VERBOSE=true wifi-wand info          # runtime
WIFIWAND_VERBOSE=true bundle exec rspec       # during tests
WIFIWAND_VERBOSE=true bundle exec rake test:all  # combined with rake task
```

**Alternative (runtime only):** Use the `-v` command-line flag instead:
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
COVERAGE_BRANCH=true bundle exec rake test:all
```

**Note:** Branch coverage is orthogonal to test scope — it can be combined with any rake task or rspec invocation. It is more detailed but slower than line coverage.

### Coverage Resultset Files

SimpleCov chooses the resultset filename from `WIFIWAND_REAL_ENV_TESTS`.

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
