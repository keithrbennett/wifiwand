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
│       ├── mac_os_model_spec.rb    # Mac OS-specific tests
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

### Automatic OS Detection

The test suite automatically detects the current operating system and runs only compatible tests:

**How it works:**
- ✅ **Tests with no OS tags** run on all OSes (common interface tests)
- ✅ **Tests with OS tags** run only on compatible OSes  
- ❌ **Tests with foreign OS tags** are automatically excluded

**Examples:**
```bash
# On Ubuntu - automatically runs:
# ✅ common_os_model_spec.rb (no OS tags)
# ✅ ubuntu_model_spec.rb (:os_ubuntu tag)
# ❌ Skips mac_os_model_spec.rb (:os_mac tag)
bundle exec rspec

# On Mac - automatically runs:
# ✅ common_os_model_spec.rb (no OS tags)  
# ✅ mac_os_model_spec.rb (:os_mac tag)
# ❌ Skips ubuntu_model_spec.rb (:os_ubuntu tag)
bundle exec rspec
```

**OS Tags Available:**
- `:os_ubuntu` - Ubuntu-specific tests
- `:os_mac` - Mac OS-specific tests
- Future: `:os_linux`, `:os_bsd`, etc.

## Test Filtering with RSpec Tags

### Available Tags

| Tag           | Description                                           | Default Behavior      |
|---------------|-------------------------------------------------------|-----------------------|
| `:disruptive` | Tests that modify system state or network connections | ❌ Excluded by default |
| `:os_ubuntu`  | Ubuntu-specific tests                                 | See OS Filtering      |
| `:os_mac`     | macOS-specific tests                                  | See OS Filtering      |

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
# Run only disruptive tests
bundle exec rspec --tag disruptive

# Run ALL tests (including disruptive)
# This environment variable bypasses all default exclusions
RSPEC_DISABLE_EXCLUSIONS=true bundle exec rspec

# Run only non-disruptive tests (default behavior)
bundle exec rspec

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
# Exclude disruptive tests by default
config.filter_run_excluding :disruptive => true

# Automatic OS detection and filtering (only if no command line tags specified)
if config.inclusion_filter.rules.empty? && config.exclusion_filter.rules.empty?
  config.filter_run do |metadata|
    # Apply default exclusion for disruptive tests
    return false if metadata[:disruptive]
    
    # Check OS compatibility for non-disruptive tests
    os_tags = metadata.keys.select { |key| key.to_s.start_with?('os_') }
    
    if os_tags.empty?
      true # No OS tags - run on all OSes (common tests)
    else
      # Test has OS tags - only run if compatible with current OS
      os_tags.include?(compatible_os_tag)
    end
  end
end
```

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

# Disruptive test - requires --tag disruptive flag
it 'turns wifi on', :disruptive do
  subject.wifi_on
  expect(subject.wifi_on?).to be(true)
end

# Disruptive test with network restoration - requires --tag disruptive flag  
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

### 3. Full Test Suite
```bash
# Before committing or deploying
bundle exec rspec --tag disruptive
```

### 4. Specific Test Files
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