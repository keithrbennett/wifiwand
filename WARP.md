# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

**wifi-wand** is a Ruby gem that provides unified WiFi management across Mac and Ubuntu systems. It operates
through both command-line interface and interactive shell modes, using OS-specific utilities under the hood
while presenting a consistent API. The gem serves as both a standalone CLI tool and a library for other Ruby
applications.

## Development Commands

### Testing
```bash
# Run non-disruptive tests (default, safe for CI/development)
bundle exec rspec

# Run specific test file
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb

# Run with verbose WiFi command output
WIFIWAND_VERBOSE=true bundle exec rspec

# Run disruptive tests only (modifies network state)
RSPEC_DISRUPTIVE_TESTS=only bundle exec rspec

# Run all tests including disruptive ones
RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec

# Run tests with branch coverage enabled
COVERAGE_BRANCH=true bundle exec rspec
```

### Development Setup
```bash
# Install dependencies
bundle install

# Build gem locally
gem build wifi-wand.gemspec

# Test the gem without installing
bundle exec exe/wifi-wand --help

# Install gem locally for system-wide testing
gem install ./wifi-wand-*.gem
```

### Interactive Testing & Debugging
```bash
# Start interactive shell for manual testing
bundle exec exe/wifi-wand -s

# Test with verbose mode to see underlying OS commands
bundle exec exe/wifi-wand -v info

# Test specific functionality
bundle exec exe/wifi-wand status
bundle exec exe/wifi-wand available_networks
```

## Architecture

### High-Level Design Pattern

The codebase follows a **layered architecture with OS abstraction**, designed to provide a unified interface
across different operating systems while encapsulating OS-specific implementation details.

#### Core Architecture Layers

1. **Entry Point Layer** (`lib/wifi-wand/main.rb`)
   - Handles command line parsing using Ruby's `optparse`
   - Manages global error handling and user-friendly error reporting
   - Routes to the CLI controller

2. **CLI Controller Layer** (`lib/wifi-wand/command_line_interface.rb`)
   - Orchestrates command execution and output formatting
   - Uses modular mixins for different concerns:
     - `HelpSystem` - documentation and help text
     - `OutputFormatter` - handles JSON, YAML, pretty print output formats
     - `CommandRegistry` - maps command aliases to methods
     - `ShellInterface` - interactive Pry-based shell

3. **OS Detection & Factory Layer** (`lib/wifi-wand/operating_systems.rb`)
   - Auto-detects current operating system
   - Creates appropriate model instances using factory pattern
   - Supports extensible OS registration for future platforms

4. **OS Abstraction Layer** (`lib/wifi-wand/os/`)
   - Defines interfaces for OS-specific behavior
   - `BaseOs` - common interface contract
   - `MacOs`, `Ubuntu` - OS detection and model creation logic

5. **Model Layer** (`lib/wifi-wand/models/`)
   - `BaseModel` - defines unified interface with wrapper methods
   - `MacOsModel` - implements macOS-specific WiFi operations using `networksetup`, `system_profiler`,
     Swift/CoreWLAN
   - `UbuntuModel` - implements Ubuntu-specific operations using `nmcli`, `iw`, `ip`

6. **Service Layer** (`lib/wifi-wand/services/`)
   - Reusable business logic components:
     - `CommandExecutor` - OS command execution with verbose logging
     - `NetworkConnectivityTester` - DNS and TCP connectivity validation
     - `NetworkStateManager` - captures/restores network state for testing
     - `StatusWaiter` - polling for desired network states
     - `ConnectionManager` - complex WiFi connection logic

### Key Architectural Patterns

#### OS Support Extension Pattern
To add support for a new operating system:
1. Create OS detector class in `lib/wifi-wand/os/` extending `BaseOs`
2. Implement model class in `lib/wifi-wand/models/` extending `BaseModel`
3. Register the new OS in the `OperatingSystems` class
4. Implement all required underscore-prefixed methods (`_connect`, `_disconnect`, etc.)

#### Command Pattern Implementation
- CLI commands are mapped through `CommandRegistry` mixin
- Commands like `cmd_co` (connect), `cmd_a` (available networks) delegate to model layer
- Interactive shell mode preserves command context between invocations

#### State Management for Testing
- **Safe Tests**: Read-only operations that don't modify network state
- **Disruptive Tests**: Modify network configuration, require cleanup
- `NetworkStateManager` captures WiFi state before tests and restores after
- Tests automatically filter based on current OS compatibility

#### Error Handling Strategy
- Custom exception hierarchy under `WifiWand::Error`
- OS command failures wrapped in `CommandExecutor::OsCommandError`
- User-friendly error messages without stack traces unless verbose mode
- Graceful degradation for optional features (public IP lookup, etc.)

### Model Layer Deep Dive

#### BaseModel Wrapper Pattern
The `BaseModel` uses a wrapper pattern where public methods check WiFi state before delegating to
underscore-prefixed implementation methods:

```ruby
# Public wrapper - checks WiFi state
def available_network_names
  wifi_on? ? _available_network_names : nil
end

# Private implementation - OS-specific
def _available_network_names
  # Implemented by subclasses
end
```

#### OS-Specific Implementation Details

**MacOsModel**:
- Primary tools: `networksetup`, `system_profiler`, `ipconfig`
- Advanced features: Swift/CoreWLAN integration for enhanced functionality
- Falls back to command-line tools when Swift/CoreWLAN unavailable
- Keychain integration for password management with detailed error handling

**UbuntuModel**:
- Primary tools: `nmcli` (NetworkManager), `iw`, `ip`
- Robust connection logic handles NetworkManager's duplicate profile issues
- Automatically selects most recent connection profiles by timestamp
- Comprehensive security type detection (WPA2/3, WEP, Open)

### Testing Architecture

#### Test Categories & Environment Variables
- `RSPEC_DISRUPTIVE_TESTS=exclude` (default): Safe, read-only tests only
- `RSPEC_DISRUPTIVE_TESTS=only`: Tests that modify network state
- `RSPEC_DISRUPTIVE_TESTS=include`: All tests including disruptive ones
- `WIFIWAND_VERBOSE=true`: Shows underlying OS commands during testing
- `COVERAGE_BRANCH=true`: Enables branch coverage analysis

#### Test Infrastructure
- SimpleCov generates HTML coverage reports in `coverage/`
- Tests auto-detect OS and filter incompatible test cases
- `ResourceManager` handles test resource cleanup
- Network state capture/restore prevents test pollution

## Key Implementation Notes

### Command Execution & Verbose Mode
All OS command execution flows through `CommandExecutor` which provides:
- Verbose logging showing exact commands run and their output
- Execution timing measurements
- Standardized error handling with exit codes
- Safe command retry mechanisms

### Interactive Shell Features
The Pry-based interactive shell (`-s` flag) provides:
- Ruby shell with full access to WiFi functionality
- Variable persistence between commands
- Built-in awesome_print formatting
- Ability to combine commands with Ruby code
- Shell command execution capabilities

### Cross-Platform Compatibility Strategy
- Unified method signatures across all OS implementations
- OS-specific tools abstracted behind common interfaces  
- Feature detection with graceful fallbacks (e.g., Swift availability on macOS)
- Comprehensive error mapping from OS-specific to user-friendly messages

### Password and Security Handling
- **macOS**: Integrates with Keychain, handles user authentication dialogs
- **Ubuntu**: Uses NetworkManager's encrypted profile storage
- No plaintext password storage in memory or logs
- Secure password comparison to avoid unnecessary profile modifications

This architecture enables rapid development of new WiFi management features while maintaining cross-platform
compatibility and testability.
