# Testing Documentation for wifi-wand

This document describes the testing setup, structure, and instructions for running tests in the wifi-wand project.

## Overview

The wifi-wand project uses RSpec for testing with a carefully designed structure that allows for safe testing of system-dependent functionality. Tests are categorized by their impact on system state, making it easy to run tests without disrupting your development environment.

## Test Structure

### Test Categories

Tests are organized into three main categories based on their system impact:

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
│       └── ubuntu_model_spec.rb    # Ubuntu-specific tests
└── integration-tests/
    └── wifi-wand/
        └── models/
            └── mac_os_model_spec.rb # Mac OS integration tests
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

### Detailed Commands

#### Safe Read-Only Tests
```bash
# Run all read-only tests
bundle exec rspec

# Run only Ubuntu model read-only tests
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb

# Run read-only tests with verbose output
bundle exec rspec --format documentation
```

#### System-Modifying Tests
```bash
# Run read-only + system-modifying tests
bundle exec rspec --tag ~network_connection

# Run only system-modifying tests
bundle exec rspec --tag modifies_system

# Run Ubuntu model tests including system-modifying
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb --tag ~network_connection
```

#### All Tests (Including Network Connections)
```bash
# Run ALL tests (high impact - will change network state)
bundle exec rspec --tag network_connection

# Run Ubuntu model tests including network connections
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb --tag network_connection
```

### Using the Convenience Script

A convenience script is available in `scripts/test.sh` for easier test execution:

```bash
# Read-only tests only (safe to run anytime)
./scripts/test.sh read-only

# Read-only + system-modifying tests (will change WiFi state)
./scripts/test.sh system-modifying

# ALL tests including network connections (high impact)
./scripts/test.sh all
```

## Test Filtering with RSpec Tags

### Available Tags

| Tag | Description | Default Behavior |
|-----|-------------|------------------|
| `:disruptive` | Tests that modify system state or network connections | ❌ Excluded by default |
| `:os_ubuntu` | Ubuntu-specific tests | See OS Filtering |
| `:os_mac` | macOS-specific tests | See OS Filtering |
| `:requires_wifi_on` | Tests that require WiFi to be on | ❌ Excluded by default |
| `:requires_available_network` | Tests that need available networks | ❌ Excluded by default |

### Tag Combinations

```bash
# Include specific tags
bundle exec rspec --tag disruptive

# Exclude specific tags  
bundle exec rspec --tag ~disruptive

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
- Cleanup procedures for system-modifying tests

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

# Disruptive test - requires --tag disruptive flag  
it 'connects to network', :disruptive do
  subject.os_level_connect('TestNetwork')
  expect(subject.connected_network_name).to eq('TestNetwork')
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
  it 'returns array when wifi is on', :requires_wifi_on do
    if subject.wifi_on?
      result = subject.available_network_names
      expect(result).to be_a(Array)
    else
      skip 'WiFi is currently off'
    end
  end
end
```

#### Safe System-Modifying Tests
```ruby
describe '#wifi_on' do
  it 'turns wifi on when it is off', :modifies_system do
    subject.wifi_off if subject.wifi_on?
    expect(subject.wifi_on?).to be(false)
    
    subject.wifi_on
    expect(subject.wifi_on?).to be(true)
  end
end
```

## Platform-Specific Testing

### Ubuntu Testing

The Ubuntu model tests are designed to run safely on Ubuntu systems:

- **File**: `spec/wifi-wand/models/ubuntu_model_spec.rb`
- **Tools tested**: `nmcli`, `iw`, `ip`
- **Safety**: Read-only tests are completely safe
- **Coverage**: Comprehensive testing of all Ubuntu-specific methods

### Mac OS Testing

For Mac OS testing, use the existing integration tests:

```bash
# Run Mac OS integration tests
bundle exec rspec integration-tests/wifi-wand/models/mac_os_model_spec.rb
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
bundle exec rspec spec/wifi-wand/common_os_model_spec.rb --tag ~modifies_system
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

### 2. Testing System Changes
```bash
# When testing system-modifying features
bundle exec rspec --tag ~network_connection
```

### 3. Full Test Suite
```bash
# Before committing or deploying
bundle exec rspec --tag network_connection
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

#### Network Manager Issues
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

# Run with debug logging
VERBOSE=true bundle exec rspec
```

#### Check System State
```bash
# Check WiFi status before/after tests
nmcli radio wifi
nmcli connection show
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

### Test Metrics

Current test coverage:
- **Ubuntu Model**: 16 examples (14 passing, 2 pending)
- **Base Model**: Error handling tests
- **Mac OS Model**: Integration tests

Target coverage: 80%+ for all core functionality

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
4. Test on both Ubuntu and Mac OS when possible
5. Ensure all tests pass before submitting pull requests

## Support

For questions about testing:
- Check existing test patterns in `spec/wifi-wand/models/`
- Review the RSpec configuration in `spec/spec_helper.rb`
- Use the convenience script in `scripts/test.sh`