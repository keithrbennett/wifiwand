# Testing Documentation for wifi-wand

This document describes the testing setup, structure, and instructions for running tests in the wifi-wand project.

## Overview

The wifi-wand project uses RSpec for testing with a carefully designed structure that allows for safe testing of system-dependent functionality. Tests are categorized by their impact on system state, making it easy to run tests without disrupting your development environment.

## Test Structure

### Test Categories

Tests are organized into two main categories based on their system impact:

* disruptive - (requires `--tag disruptive` to run) any tests that can potentially modify the system
* nondisruptive - (default test suite run mode or with `--tag ~disruptive`) all other tests

**Note:** The `~` symbol in RSpec means "NOT" - so `--tag ~disruptive` means "run all tests that are NOT tagged as disruptive".


#### 1. Read-only Tests (Default)
- **Safety Level**: ✅ Safe to run anytime
- **System Impact**: No changes to system state
- **Network Impact**: No disruption to connectivity
- **Default Behavior**: These are the only tests that run by default

**Includes tests for:**
- WiFi interface detection
- WiFi status checking
- Network information retrieval
- MAC address queries
- Nameserver queries
- Password retrieval (read-only)

#### 2. Disruptive Tests (`:disruptive`)
- **Safety Level**: 🔴 High impact  
- **System Impact**: Changes WiFi state and connections
- **Network Impact**: Will disrupt current connectivity
- **Required Flag**: `--tag disruptive`
- **Automatic Restoration**: ✅ Network state is captured and restored when possible

**Network Restoration Features:**
- Automatic network state capture before running disruptive tests
- Automatic reconnection to your original network after each disruptive test completes and after the entire test suite has completed
- On macOS: May prompt for keychain access permissions to retrieve network passwords
- Graceful fallback: If restoration fails, warns user to manually reconnect
- Individual tests can call `restore_network_state` to restore connection mid-test

**Performance Considerations (Disruptive Tests):** The automatic network restoration for disruptive tests, while robust, has a significant performance impact. When the disruptive test suite is initiated from a connected state, each test triggers a slow network reconnection, which can make the suite run up to 5 times slower. For a much faster test cycle, you can run the disruptive tests after manually disconnecting from Wi-Fi (either by turning Wi-Fi off or disconnecting from the network). This avoids the lengthy reconnection process after each test. While this approach skips a small amount of connection-related test logic (like the `disconnect` test), it covers the vast majority of functionality and is ideal for rapid, iterative development.

**Includes tests for:**
- Turning WiFi on/off
- Network disconnection  
- Connecting to WiFi networks
- Network authentication
- Removing preferred networks
- Setting nameservers
- Connection error handling

### Test Files

```
spec/
├── spec_helper.rb                 # RSpec configuration and tagging setup
├── wifi-wand/
│   ├── common_os_model_spec.rb     # OS-agnostic interface tests (NEW)
│   └── models/
│       ├── base_model_spec.rb      # Error handling tests
│       ├── mac_os_model_spec.rb    # macOS-specific tests
│       └── ubuntu_model_spec.rb    # Ubuntu-specific tests
```

## Running Tests

### Quick Start

```bash
# Install dependencies
bundle install

# Run tests appropriate for current OS (automatic OS detection)
bundle exec rspec
```

### ⚠️ IMPORTANT: CI Configuration

**DO NOT run disruptive tests in CI environments.**

Disruptive tests will fail or cause problems in CI because:
- CI runners typically lack WiFi hardware
- Modifying network state will disrupt the CI server
- CI runners may not be running a supported OS (macOS or Ubuntu)

**The default behavior (`RSPEC_DISRUPTIVE_TESTS` unset) runs only safe, read-only tests.** Never set `RSPEC_DISRUPTIVE_TESTS=include` or `RSPEC_DISRUPTIVE_TESTS=only` in your CI configuration.

### Automatic OS Detection

The test suite automatically detects the current operating system. Mocked unit tests run on any host; only tests that exercise real hardware are gated to a specific OS.

**How it works:**
- ✅ **Tests with no OS tag** run on all OSes
- ✅ **Tests tagged `:disruptive_mac`** run only on macOS (and only when disruptive tests are enabled)
- ✅ **Tests tagged `:disruptive_ubuntu`** run only on Ubuntu (and only when disruptive tests are enabled)
- ❌ **Tests tagged with a foreign OS** are automatically skipped

**Examples:**
```bash
# On Ubuntu - automatically runs:
# ✅ All mocked unit tests in ubuntu_model_spec.rb and mac_os_model_spec.rb
# ✅ :disruptive_ubuntu tests (if RSPEC_DISRUPTIVE_TESTS=include)
# ❌ Skips :disruptive_mac tests
bundle exec rspec

# On macOS - automatically runs:
# ✅ All mocked unit tests in ubuntu_model_spec.rb and mac_os_model_spec.rb
# ✅ :disruptive_mac tests (if RSPEC_DISRUPTIVE_TESTS=include)
# ❌ Skips :disruptive_ubuntu tests
bundle exec rspec
```

**Combined OS+Disruptive Tags:**
- `:disruptive_mac` - requires macOS hardware; always excluded by default (same as `:disruptive`)
- `:disruptive_ubuntu` - requires Ubuntu hardware; always excluded by default (same as `:disruptive`)
- Future: `:disruptive_linux`, `:disruptive_bsd`, etc.

**Choosing the right tag:**
Use plain `:disruptive` when the test works on any supported OS — typically tests that use `create_test_model`, which adapts to the current OS and exercises the common interface. Use `:disruptive_mac` or `:disruptive_ubuntu` only when the test requires OS-specific hardware, commands, or model behavior that would not work on another OS.

## Test Filtering with RSpec Tags

### Available Tags

| Tag                  | Description                                              | Default Behavior      |
|----------------------|----------------------------------------------------------|-----------------------|
| `:disruptive`        | Tests that modify system state or network connections    | ❌ Excluded by default |
| `:disruptive_mac`    | Disruptive tests that also require macOS hardware        | ❌ Excluded by default |
| `:disruptive_ubuntu` | Disruptive tests that also require Ubuntu hardware       | ❌ Excluded by default |

### Sudo/Keychain Ordering

- Tests tagged `:needs_sudo_access` (for example, those that invoke `sudo networksetup ...`) are ordered to run first across the entire suite to surface authentication prompts early.
- On macOS (non‑CI), the suite performs a brief preflight before tests begin:
  - Warm the `sudo` timestamp (`sudo -v`).
  - Attempt a harmless `sudo networksetup -removepreferredwirelessnetwork <iface> non_existent_network_123` to front‑load any prompt.
  - If a current SSID is available and a TTY is present, a preferred network password lookup is attempted to surface any Keychain prompt early (see Keychain stubbing below).

## Verbose Testing Mode

The test suite includes built-in support for verbose mode, which shows the actual OS commands being executed and their outputs during testing. This is extremely helpful for debugging test failures and understanding what wifi-wand is doing under the hood.

### Environment Variable Control

Use the `WIFIWAND_VERBOSE` environment variable to enable verbose mode:

```bash
# Enable verbose mode for all tests
WIFIWAND_VERBOSE=true bundle exec rspec
```

### Test-Level Override

Individual tests can override the environment variable setting:

```ruby
# Force verbose mode for this specific test (even if WIFIWAND_VERBOSE=false)
subject { create_test_model(verbose: true) }

# Force quiet mode for this specific test (even if WIFIWAND_VERBOSE=true)  
subject { create_test_model(verbose: false) }

# Use environment setting (default behavior)
subject { create_test_model }
```

### What Verbose Mode Shows

When verbose mode is enabled, you'll see:

- **OS Commands**: The exact command line being executed (e.g., `nmcli device wifi list`)
- **Command Duration**: How long each command took to execute
- **Command Output**: The raw stdout/stderr from each command

**Example verbose output:**
```
Attempting to run OS command: nmcli device wifi list
Duration: 0.1234 seconds
Command result:
IN-USE  BSSID              SSID         MODE   CHAN  RATE        SIGNAL  BARS  SECURITY  
*       AA:BB:CC:DD:EE:FF  MyNetwork    Infra  6     130 Mbit/s  72      ▂▄▆_  WPA2
```

### Helper Methods

The test suite provides centralized helper methods for creating models:

- `create_test_model(options = {})` - Creates model for current OS
- `create_ubuntu_test_model(options = {})` - Creates Ubuntu model specifically  
- `create_mac_os_test_model(options = {})` - Creates macOS model specifically

These methods automatically handle:
- ✅ Verbose mode configuration from `WIFIWAND_VERBOSE`
- ✅ Test-specific option overrides
- ✅ Proper model initialization with `create_model` factory method

### Tag Combinations

```bash
# Run disruptive tests only
RSPEC_DISRUPTIVE_TESTS=only bundle exec rspec

# Run ALL native OS tests (including disruptive)
RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec

# Run only non-disruptive tests (default behavior)
bundle exec rspec

# Run only non-disruptive tests (explicitly)
RSPEC_DISRUPTIVE_TESTS=exclude bundle exec rspec

# Focus on specific tests
bundle exec rspec --tag focus
```

## Test Configuration

### RSpec Configuration (`.rspec`)

```ruby
--format documentation
--color
--require spec_helper
```

### Spec Helper (`spec/spec_helper.rb`)

The spec helper includes:
- Custom tag definitions
- Default filtering configuration
- Automatic OS detection and filtering
- Test documentation on startup
- Cleanup procedures for disruptive tests

Key configuration:
```ruby
# :disruptive_mac / :disruptive_ubuntu backfill :disruptive so all existing
# filtering, after-hooks, and network-state management apply automatically
config.define_derived_metadata do |meta|
  meta[:disruptive] = true if meta[:disruptive_mac] || meta[:disruptive_ubuntu]
  meta[:slow] = true if meta[:disruptive]
end

# Exclude disruptive tests by default (catches :disruptive_mac/:disruptive_ubuntu too)
config.filter_run_excluding :disruptive => true

# OS filtering: skip tests tagged for a different OS
# (runs in before(:each) so it only fires for examples that weren't already excluded)
```

Additional important configuration:

- Sudo‑first ordering: examples and groups tagged `:needs_sudo_access` are scheduled at the start of the run.
- macOS preflight (non‑CI only): warms `sudo` and front‑loads a harmless `networksetup` command; attempts an optional Keychain lookup.
- macOS Keychain stubbing: by default, the suite stubs preferred password reads to avoid GUI prompts. Real Keychain access is not performed in normal runs.

The OS detection:
- Evaluates once per test run (efficient)
- Automatically excludes foreign OS tests
- Runs common tests on all platforms
- Falls back gracefully if OS detection fails
```

## Writing Tests

### Adding New Tests

When adding tests, categorize them appropriately:

```ruby
# Read-only test (safe) - runs by default
it 'returns wifi status' do
  result = subject.wifi_on?
  expect(result).to be(true).or(be(false))
end

# Disruptive test (any OS) - excluded by default
it 'turns wifi on', :disruptive do
  subject.wifi_on
  expect(subject.wifi_on?).to be(true)
end

# Disruptive test requiring specific OS hardware - excluded by default
it 'turns wifi on', :disruptive_mac do
  subject.wifi_on
  expect(subject.wifi_on?).to be(true)
end

# Disruptive test with network restoration - excluded by default
it 'tests disconnect and restores connection', :disruptive do
  
  original_network = subject.connected_network_name
  subject.disconnect
  expect(subject.connected_network_name).to be_nil
  
  # Restore the original network connection
  restore_network_state
  expect(subject.connected_network_name).to eq(original_network)
end
```

### Test Structure Patterns

#### Read-Only Tests
```ruby
describe '#wifi_on?' do
  it 'returns boolean indicating wifi status' do
    result = subject.wifi_on?
    expect(result).to be(true).or(be(false))
  end
end
```

#### Conditional Tests
```ruby
describe '#available_network_names' do
  it 'returns array when wifi is on' do
    if subject.wifi_on?
      result = subject.available_network_names
      expect(result).to be_a(Array)
    else
      skip 'WiFi is currently off'
    end
  end
end
```

#### Disruptive Tests
```ruby
describe '#wifi_on' do
  it 'turns wifi on when it is off', :disruptive do
    subject.wifi_off if subject.wifi_on?
    expect(subject.wifi_on?).to be(false)
    
    subject.wifi_on
    expect(subject.wifi_on?).to be(true)
  end
end
```

## Platform-Specific Testing

The test suite includes tests specific to the supported operating systems.

Tests for operating systems _not_ the currently running one are automatically excluded.

```bash
# Run macOS integration tests
bundle exec rspec spec/wifi-wand/models/mac_os_model_spec.rb
```

## OS-Agnostic Testing

### Common Interface Tests

The `common_os_model_spec.rb` file provides OS-agnostic testing that automatically adapts to whatever operating system is running the tests:

**Key Features:**
- **Automatic OS Detection**: Instantiates the correct model for the current OS
- **Interface Contract Testing**: Ensures all OS models implement the same interface
- **Cross-Platform Compatibility**: Single test suite works on Ubuntu, Mac, and future OSes
- **Future-Proof**: New OS models automatically get tested without adding new specs

**How It Works:**
```ruby
# Automatically detects OS and instantiates appropriate model
subject do
  os_detector = WifiWand::OperatingSystems.new
  current_os = os_detector.current_os
  current_os.create_model(OpenStruct.new(verbose: false))
end

# Tests run on any OS with consistent expectations
describe '#internet_tcp_connectivity?' do
  it 'returns boolean indicating TCP connectivity' do
    result = subject.internet_tcp_connectivity?
    expect([true, false]).to include(result)
  end
end
```

**Running Common Tests:**
```bash
# Runs on current OS (Ubuntu, Mac, etc.)
bundle exec rspec spec/wifi-wand/common_os_model_spec.rb

# Safe to run on any OS
bundle exec rspec spec/wifi-wand/common_os_model_spec.rb --tag ~disruptive
```

**Benefits:**
- **Single Source of Truth**: All OS models must implement the same interface
- **No Duplication**: Don't need to add tests for new OS models
- **Consistent Behavior**: Ensures the same expectations across all platforms
- **Automatic Validation**: New OS models are immediately validated

**Interface Requirements:**
All OS models must implement these methods with consistent return types:
- `internet_tcp_connectivity?` → Boolean
- `dns_working?` → Boolean  
- `default_interface` → String or nil
- `wifi_info` → Hash with consistent structure
- And all other base model methods

### Adding New OS Models

When adding support for a new OS:

1. **Implement the interface**: Ensure all required methods are implemented
2. **Run common tests**: `bundle exec rspec spec/wifi-wand/common_os_model_spec.rb`
3. **Add OS-specific tests**: Create OS-specific test file for implementation details
4. **Update documentation**: Add any OS-specific testing considerations

The common tests will automatically validate that the new OS model correctly implements the expected interface.

## Test Development Workflow

### 1. Development (Safe)
```bash
# Run read-only tests continuously during development
bundle exec rspec --format documentation
```

### 2. Testing Disruptive Features
```bash
# When testing disruptive features
bundle exec rspec --tag disruptive
```

Note: In CI (`ENV['CI']` present), disruptive tests are always skipped.

### 3. Full Test Suite
```bash
# Before committing or deploying
bundle exec rspec --tag disruptive
```

### 4. Maximum Coverage Testing

For the highest test coverage, ensure optimal network configuration:

```bash
# Ensure WiFi is the only active internet connection
# Disconnect Ethernet, mobile hotspots, or other network interfaces
# Then run all tests including disruptive ones:
RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec
```

**Important**: Maximum code coverage can only be achieved by running the complete test suite (`RSPEC_DISRUPTIVE_TESTS=include`), and it requires that **WiFi be the only active internet connection**. Other network interfaces (Ethernet, mobile hotspot, etc.) can cause certain WiFi-specific code paths to be skipped.

This happens because:
- Many network connectivity tests will use non-WiFi interfaces when available
- WiFi-specific error handling and edge cases may not trigger
- The `default_interface` detection behaves differently with multiple active connections

### 5. Specific Test Files
```bash
# Test specific functionality
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb
```

## Troubleshooting

### Common Issues

#### Test Failures Due to Network Disconnection
**Problem**: Tests turn off WiFi, disconnecting your development session
**Solution**: The new Ubuntu tests are designed to avoid this. If using older tests, run only read-only tests.

#### Interface Detection Failures
**Problem**: Tests can't find WiFi interface
**Solution**: 
```bash
# Check available interfaces manually
iw dev
nmcli device status
```

#### Permission Errors
**Problem**: Tests fail due to insufficient permissions
**Solution**: Run with appropriate privileges if needed:
```bash
sudo bundle exec rspec
```

On macOS, authentication prompts are surfaced at the start of the suite when possible (non‑CI). Tests that need sudo are also ordered first.

#### NetworkManager Issues
**Problem**: Tests interact with NetworkManager
**Solution**: Ensure NetworkManager is running:
```bash
systemctl status NetworkManager
```

### Debug Tips

#### Enable Verbose Mode
```bash
# Run tests with verbose output
bundle exec rspec --format documentation --backtrace

# Run with wifi-wand verbose mode (shows OS commands and their outputs)
WIFIWAND_VERBOSE=true bundle exec rspec

# Run specific tests with verbose mode
WIFIWAND_VERBOSE=true bundle exec rspec --tag disruptive
```

#### Check System State
```bash
# Check WiFi status before/after tests
nmcli radio wifi
nmcli connection show
nmcli device status

# Check specific WiFi interface
iw dev
iwconfig

# Verify NetworkManager service
systemctl status NetworkManager

# Check for conflicting network managers
ps aux | grep -E "(wpa_supplicant|dhcpcd|connman)"

# Test basic connectivity
ping -c 3 8.8.8.8
nslookup google.com
```

#### Isolate Test Failures
```bash
# Run specific failing test
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb:15
```

## Continuous Integration

### GitHub Actions Considerations

When setting up CI/CD:

1. **Read-only tests**: Can run safely in any environment
2. **System-modifying tests**: Require privileged environment
3. **Network connection tests**: May not be suitable for CI

Example CI configuration focus:
```yaml
- name: Run safe tests
  run: bundle exec rspec
```

The CI job intentionally skips all tests tagged `:disruptive` to avoid modifying the network stack of the runner.

## macOS Specifics

### Keychain Access in Tests

- By default, tests do not perform real Keychain reads for preferred Wi‑Fi passwords. The suite stubs these calls to avoid GUI prompts and non‑determinism.

### Interface Detection Performance

- macOS interface detection prefers the fast `networksetup -listallhardwareports` path, falling back to `system_profiler` when needed. This improves test performance without changing behavior.


## Best Practices

1. **Always run read-only tests first** to ensure basic functionality
2. **Use appropriate tags** for new tests based on their system impact
3. **Test system state, not implementation details** for system-dependent code
4. **Handle gracefully when resources are unavailable** (WiFi off, no networks, etc.)
5. **Document any test that modifies system state** clearly with tags
6. **Test both success and failure scenarios** for network operations
7. **Use mocks sparingly** for system operations - prefer real command execution

## Contributing

When contributing tests:

1. Follow the existing tag conventions
2. Add new tests to appropriate files
3. Update this documentation if adding new test categories
4. Test on both Ubuntu and macOS when possible
5. Ensure all tests pass before submitting pull requests

## Support

For questions about testing:
- Check existing test patterns in `spec/wifi-wand/models/`
- Review the RSpec configuration in `spec/spec_helper.rb`
