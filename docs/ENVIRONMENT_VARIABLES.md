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
- **Overrides:** Later command-line arguments can override most defaults, but options without a disabling form (e.g., `--shell`) cannot currently be negated.
- **Scope:** `WIFIWAND_OPTS` only supports top-level flags; subcommand options (like `log --file`) must still be passed on the command line when you invoke the subcommand.
- **Parsing errors:** If the value contains unmatched quotes or otherwise cannot be parsed, wifi-wand aborts with a configuration error.

## Test Configuration Variables

### `RSPEC_DISRUPTIVE_TESTS`

Control which test categories run.

**Values:**
- `exclude` or unset (default) - Only safe, read-only tests
- `only` - Only tests that modify network state
- `include` - All tests including disruptive ones

**Usage:**
```bash
# Default: safe tests only
bundle exec rspec

# Run only disruptive tests
RSPEC_DISRUPTIVE_TESTS=only bundle exec rspec

# Run all tests
RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec
```

**⚠️ WARNING:** Never use `only` or `include` in CI environments. Disruptive tests require WiFi hardware and will modify network state.

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

## CI/CD Guidelines

**Default behavior is CI-safe:** When `RSPEC_DISRUPTIVE_TESTS` is unset, only safe, read-only tests run.

**Never set these in CI:**
- `RSPEC_DISRUPTIVE_TESTS=include`
- `RSPEC_DISRUPTIVE_TESTS=only`

**Why?**
- CI runners typically lack WiFi hardware
- Modifying network state disrupts the CI server
- CI may not be running a supported OS (macOS or Ubuntu)

See [Testing Documentation](TESTING.md) for more details.
