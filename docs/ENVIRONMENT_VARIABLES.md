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

### `RSPEC_KEYCHAIN_PREFLIGHT`

Controls macOS keychain access preflight check behavior.

**Usage:** Internal test configuration - rarely needs manual adjustment.

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
