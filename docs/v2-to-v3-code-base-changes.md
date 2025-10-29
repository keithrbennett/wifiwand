# Version 2.x to 3.0 Code Base Changes

This document summarizes the changes and improvements made in version 3.0 compared to version 2.x.

## Configuration & Testing Infrastructure

- Added `.rspec` configuration file with documentation format, color output, and automatic spec_helper loading
- Created comprehensive testing documentation in `docs/TESTING.md` covering test categories, OS detection, and verbose mode
- Implemented automatic OS detection and filtering in test suite to run only compatible tests
- Added support for disruptive vs non-disruptive test categorization with automatic network state restoration

## Ubuntu Linux Support

- Added full Ubuntu Linux support alongside existing macOS functionality
- Implemented `UbuntuModel` class using `nmcli`, `iw`, and `ip` command-line tools
- Created Ubuntu-specific test suite with comprehensive coverage of WiFi operations
- Added OS abstraction layer in `lib/wifi-wand/os/` for clean separation of OS-specific logic

## Enhanced Documentation

- Completely rewrote README.md with improved structure, quick start guide, and clearer explanations
- Added detailed interactive shell usage examples and variable shadowing explanations
- Updated installation instructions and troubleshooting sections
- Expanded code examples for both command-line and library usage
- Added contact information and updated project description for cross-platform support

## Test Suite Improvements

- Created OS-agnostic common interface tests that work across all supported platforms
- Added tags to enable separation of disruptive (to system) and nondisruptive tests; default mode runs only nondisruptive tests
- Made verbose mode accessible to tests via a WIFIWAND_VERBOSE environment variable
- Implemented automatic network state capture and restoration for disruptive tests
- Added helper methods for consistent test model creation across different OS platforms

## Code Architecture Enhancements

- Improved separation between OS detection, model creation, and command execution
- Added proper error handling for unsupported operating systems
- Enhanced the factory pattern for creating OS-specific models
- Maintained backward compatibility while adding new platform support

## Release Notes Updates

- Updated terminology from "Mac OS" to "macOS" throughout documentation
- Prepared version bump to 3.0.0-alpha indicating major platform expansion

## Interactive Shell Improvements

- Suppressed pry stack traces for exceptions to provide a cleaner, more user-friendly shell experience. Errors now display a simple message without internal implementation details.

## Event Logging System (New Feature)

- Added comprehensive event logging system with the `log` command
- Continuously monitors WiFi status and logs state changes at configurable intervals
- Tracks six event types: WiFi on/off, network connect/disconnect, internet available/unavailable
- Multiple output modes:
  - Default: stdout only
  - `--file [PATH]`: log to file (default: `wifiwand-events.log`)
  - `--file --stdout`: output to both file and terminal
- Configurable polling interval with `--interval N` (default: 5 seconds)
- Graceful shutdown with Ctrl+C
- ISO-8601 timestamp format for all logged events
- Created `LogCommand` class for command-line option parsing
- Created `EventLogger` service for monitoring and event detection
- Created `LogFileManager` service for file output handling
- Added comprehensive logging documentation in `docs/LOGGING.md`

## Event Hooks System (New Feature)

- Fully implemented event hook system for automation and notifications
- Hooks receive JSON event data via stdin with full state information
- Event JSON includes: type, timestamp, details, previous_state, current_state
- Hook execution with proper error handling and exit code checking
- Default hook location: `~/.config/wifi-wand/hooks/on-event`
- Created example hooks in `examples/log-notification-hooks/`:
  - `on-wifi-event-syslog.rb` - Send events to system syslog
  - `on-wifi-event-json-log.rb` - Log events as NDJSON for analysis
  - `on-wifi-event-slack.rb` - Post formatted events to Slack
  - `on-wifi-event-webhook.rb` - POST events to HTTP endpoints
  - `on-wifi-event-macos-notify.rb` - macOS Notification Center (via terminal-notifier)
  - `on-wifi-event-gnome-notify.rb` - GNOME/Ubuntu desktop notifications
  - `on-wifi-event-kde-notify.rb` - KDE Plasma desktop notifications
  - `on-wifi-event-multi.rb` - Compound hook for running multiple hooks
- Hook execution integrated into EventLogger with stdin/stdout pipe handling
- Added hook testing infrastructure and sample events
- Comprehensive hook documentation in `examples/log-notification-hooks/README.md`

## Status Command (New Feature)

- Added comprehensive `status` command for real-time connectivity monitoring
- Displays WiFi power state, network connection, TCP connectivity, DNS resolution, and overall internet status
- Progressive display for interactive terminals (TTY mode) - results appear incrementally as they become available
- Implements `BaseModel#status_line_data` method for structured status data
- Progress callback architecture for non-blocking status checks
- Proper timeout handling for connectivity checks to avoid false negatives
- Works in both interactive shell mode and command-line mode
- Supports post-processing with output formatters (JSON, YAML, etc.)

## License Change

- Changed project license from MIT to Apache License 2.0
- Updated all license references throughout documentation

## Test Coverage Enhancements

- Added strict coverage enforcement with `COVERAGE_STRICT=true` environment variable
  - Enforces minimum 80% overall coverage
  - Enforces minimum 70% per-file coverage
- Added branch coverage support with `COVERAGE_BRANCH=true` environment variable
- Implemented coverage grouping by component (Models, Services, OS Detection, Core)
- Created `CoverageConfig` module in `spec/support/coverage_config.rb`
- Greatly expanded test coverage across:
  - Model classes (MacOsModel, UbuntuModel, BaseModel)
  - Service classes (EventLogger, LogFileManager, ConnectionManager)
  - CLI components (CommandLineInterface, CommandRegistry, OutputFormatter)
- Added comprehensive test documentation in `CLAUDE.md` with:
  - Testing strategy for different modes (safe, disruptive, OS-specific)
  - Test refactoring guidelines for unified patterns
  - Complete test style guide with data structures and assertion patterns
  - Coverage priorities and best practices

## QR Code Generation Improvements

- Fixed QR code generation to properly connect to networks (not just open WiFi)
- Added support for hidden networks in QR code generation
- Added optional password parameter to avoid macOS authentication prompts
- Improved argument handling (changed from string to array)
- Enhanced interactive mode display instructions in README

## Git Hooks

- Added pre-commit hook that automatically runs safe tests before commits
- Created `bin/setup-hooks` script for easy hook installation
- Hooks stored in tracked `hooks/` directory and copied to `.git/hooks/`
- Updated documentation with setup instructions for new developers

## Architecture Improvements

- Created modular command structure with `LogCommand` in `lib/wifi-wand/commands/`
- Extracted timing constants into `TimingConstants` module for consistency
- Improved error handling with proper exit codes for hook execution
- Enhanced I/O routing with separate output and error streams
- Better separation of concerns between CLI, models, and services
