# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---
hooks:
  on_wait_for_user:
    handler: notify-send "Claude Code" "Waiting for your response"
---

## Project Overview

**wifi-wand** is a Ruby gem that provides cross-platform WiFi management for Mac and Ubuntu systems. 
It operates through both command-line interface and interactive shell modes, 
using OS-specific utilities under the hood while presenting a unified API.

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

# Run tests with branch coverage enabled
COVERAGE_BRANCH=true bundle exec rspec
```

### Development Setup
```bash
# Install dependencies
bundle install

# Set up git hooks (run once after cloning)
bin/setup-hooks

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

### Test Coverage
- SimpleCov generates coverage reports automatically when running tests
- HTML reports are saved to `coverage/index.html`
- Coverage is grouped by component (Models, Services, OS Detection, Core)
- Branch coverage can be enabled with `COVERAGE_BRANCH=true`

### Test Refactoring Guidelines

When improving test coverage or adding new tests, follow these patterns to eliminate duplication:

#### Unified Testing Pattern for Methods with Contextual Behavior
For methods that behave differently based on context/configuration (e.g., TTY status, user permissions, feature flags),
use this unified pattern:

```ruby
# Shared examples for methods with contextual behavior
shared_examples 'contextual method' do |test_cases|
  test_cases[:tests].each do |description, data|
    it description do
      # Set up context/configuration based on test data
      allow($stdout).to receive(:tty?).and_return(data[:context_flag]) if data.key?(:context_flag)
      allow(subject).to receive(:some_config).and_return(data[:config_value]) if data.key?(:config_value)
      
      result = subject.public_send(test_cases[:method_name], data[:input])
      expect(result).to eq(data[:expected_output])
      
      # Verify context-dependent behavior (example: colorization)
      if data.key?(:verify_pattern)
        expected_behavior = data[:context_flag] && data.fetch(:special_case, true)
        expect(result.match?(data[:verify_pattern])).to eq(expected_behavior)
      end
    end
  end
end

# Usage with embedded context settings (colorization example)
include_examples 'contextual method', {
  method_name: :colorize_status,
  tests: {
    'colorizes when context enabled'    => { input: 'true', expected_output: "\e[32mtrue\e[0m", context_flag: true,  verify_pattern: /\e\[\d+m/ },
    'returns plain text when disabled' => { input: 'true', expected_output: 'true',              context_flag: false, verify_pattern: /\e\[\d+m/ },
    'handles edge case when enabled'    => { input: 'unknown', expected_output: 'unknown',       context_flag: true,  verify_pattern: /\e\[\d+m/, special_case: false }
  }
}
```

#### Key Principles
1. **Embed context settings in test data** instead of separate context blocks
2. **Use edge case flags** for special behaviors that don't follow normal patterns (e.g., `special_case: false`)
3. **Properly verify both scenarios**: Test behavior when context is enabled/disabled
4. **Avoid duplicate context blocks** - unify different contextual states in single test structure
5. **Use data-driven testing** with hashes for cleaner test organization

### Complete Test Style Guide

When creating comprehensive test files, follow these patterns for consistency and maintainability:

#### File Structure
```ruby
describe Module::ClassName do
  # Extract repeated regex patterns into constants at the top
  ANSI_COLOR_REGEX = /\e\[\d+m/
  GREEN_TEXT_REGEX = /\e\[32m.*\e\[0m/
  # ...
   
  # Test setup with mocks
  let(:mock_dependencies) { ... }
  subject { ... }
  
  # Shared examples for similar behavior patterns
  shared_examples 'behavior pattern' do |test_cases|
    # Implementation
  end
  
  # Individual method tests
end
```

#### Data Structure Standards
- **Hash alignment**: All fields start at same column positions
- **Descriptive keys**: Test names clearly indicate expected behavior
- **Embedded configuration**: Include all test parameters in data structure
- **Semantic constants**: Extract repeated regex/values into named constants

#### Assertion Patterns
- **Format-agnostic**: Test logical content, not exact formatting (`/WiFi.*ON/` not `"WiFi: ON"`)
- **Comprehensive verification**: Test both positive and negative cases
- **Color code validation**: Use extracted regex constants consistently
- **Mock isolation**: Never call real system methods in tests

#### Test Organization
- **Shared examples**: For methods with similar TTY/non-TTY patterns
- **Data-driven tests**: Use hashes/arrays for multiple similar test cases  
- **Edge case handling**: Include `has_color: false` for non-colorizing cases
- **Brittle test avoidance**: Use regex patterns instead of exact string matching

#### Coverage Priorities
1. **All public methods** with comprehensive test cases
2. **TTY vs non-TTY behavior** for colorization methods
3. **Edge cases and error conditions** with proper mocking
4. **Format flexibility** to avoid brittle tests
5. **Regex extraction** to eliminate duplication

#### Example Implementation
```ruby
# Bad - brittle exact matching
expect(result).to eq("WiFi: \e[32mON\e[0m | Network: \e[36m\"Test\"\e[0m")

# Good - flexible pattern matching  
expect(result).to match(/WiFi.*ON/)
expect(result).to match(GREEN_TEXT_REGEX)
expect(result).to match(CYAN_TEXT_REGEX)
```

Apply these patterns proactively when creating new test files to ensure consistency across the codebase.

## Git Hooks

The repository includes git hooks to maintain code quality:

### Pre-commit Hook
- Automatically runs `bundle exec rspec` (safe tests) before each commit
- Prevents commits if tests fail
- Installed via `bin/setup-hooks` script

### Setup for New Developers
```bash
# After cloning the repository, run:
bin/setup-hooks
```

This copies hooks from the tracked `hooks/` directory to `.git/hooks/` and makes them executable.

## Code Conventions

- Ruby 2.7+ required
- Uses `awesome_print` for formatted output
- Pry for interactive shell with `reline` for readline operations
- OpenStruct for configuration objects
- Modular design with clear separation of concerns
