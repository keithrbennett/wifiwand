# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---
hooks:
  on_wait_for_user:
    handler: notify-send "Claude Code" "Waiting for your response"
---

## Project Overview

**wifi-wand** is a Ruby gem that provides cross-platform WiFi management for Mac and Ubuntu systems. It operates through both command-line interface and interactive shell modes, using OS-specific utilities under the hood while presenting a unified API.

## Development Commands

### Testing
```bash
# Run non-disruptive tests (default, safe for CI/development)
bundle exec rspec

# Run non-disruptive tests (explicitly)
RSPEC_DISRUPTIVE_TESTS=exclude bundle exec rspec

# Run specific test file
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb

# Run with verbose WiFi command output
WIFIWAND_VERBOSE=true bundle exec rspec

# Run disruptive tests only
RSPEC_DISRUPTIVE_TESTS=only bundle exec rspec

# Run all native OS tests (disruptive + non-disruptive)
RSPEC_DISRUPTIVE_TESTS=include bundle exec rspec
```

### Development Setup
```bash
# Install dependencies
bundle install

# Build gem locally
gem build wifi-wand.gemspec

# Test the gem without installing
bundle exec exe/wifi-wand --help
```

### Interactive Testing
```bash
# Start interactive shell for manual testing
bundle exec exe/wifi-wand -s

# Test with verbose mode to see underlying OS commands
bundle exec exe/wifi-wand -v info
```

## Architecture

### Core Architecture
The codebase follows a layered architecture with OS abstraction:

- **Entry Point**: `lib/wifi-wand/main.rb` - handles command line parsing
- **CLI Controller**: `lib/wifi-wand/command_line_interface.rb` - orchestrates commands and output
- **OS Detection**: `lib/wifi-wand/operating_systems.rb` - detects current OS and creates appropriate models
- **OS Abstractions**: `lib/wifi-wand/os/` - defines OS-specific behavior interfaces
- **Model Layer**: `lib/wifi-wand/models/` - implements WiFi operations for each OS
- **Service Layer**: `lib/wifi-wand/services/` - reusable business logic

### OS Support Pattern
New operating systems are added by:
1. Creating OS detector in `lib/wifi-wand/os/`
2. Implementing model in `lib/wifi-wand/models/`
3. Registering in `OperatingSystems` class

### Command Line Interface Architecture
The CLI uses modular design with mixins:
- `HelpSystem` - handles help text and documentation
- `OutputFormatter` - formats output (JSON, YAML, pretty print)
- `ErrorHandling` - manages error messages and recovery
- `CommandRegistry` - maps command aliases to methods
- `ShellInterface` - interactive shell using Pry

### Key Models
- **BaseModel** - common interface for all OS implementations
- **MacOsModel** - macOS-specific WiFi operations using `networksetup`, `system_profiler`
- **UbuntuModel** - Ubuntu-specific operations using `nmcli`, `iw`, `ip`

## Testing Strategy

### Test Categories
- **Safe Tests** (default): Read-only operations, safe for CI
- **Disruptive Tests**: Modify network state, require manual cleanup
- **OS-Specific Tests**: Automatically filtered based on current OS

### Test Environment
- Tests automatically detect current OS and filter incompatible tests
- Network state is captured/restored for disruptive tests
- Use `WIFIWAND_VERBOSE=true` to debug underlying OS commands
- ResourceManager tracks and cleans up test resources

## Code Conventions

- Ruby 2.7+ required
- Uses `awesome_print` for formatted output
- Pry for interactive shell with `reline` for readline operations
- OpenStruct for configuration objects
- Modular design with clear separation of concerns
