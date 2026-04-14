# AGENTS.md

This file provides guidance to AI agents (such as Gemini CLI, Claude Code, etc.) when working with code in
this repository. Treat it as the canonical reference for workflows, tooling, and expectations; update it
directly whenever new agent instructions are required.

## Mission
- Pull accurate information and project facts for users by driving available tools rather than reasoning from
  scratch.
- Keep workflow transparent: explain what you did, why it matters, and what the user should consider next.
- Leave the repository tidy; only touch files that advance the request. If you find other opportunities for
  improvement along the way, mention them in the form of a prompt the user can use later.

## Running External Commands

- When running shell commands on this project, use a Bash login shell where possible: run commands via `bash
  -lc '<command>'` (or the platform's equivalent) rather than relying on the default shell.
- If practical, use workdir features of the agent rather than relying on `cd` in the command string.

## Environment & Execution

Prefer project-local tools and scripts (for example, `bin/` scripts, `package.json` scripts, Makefile targets)
instead of ad-hoc one-off commands when building, testing, or running the project.

- Prefer `rg`/`rg --files` for searches; switch only if ripgrep is unavailable.
- Planning tool: skip for trivial chores; otherwise create a multi-step plan and keep it updated as you work
  (max one `in_progress` step).
- When moving or renaming tracked files, use `git mv` (or `git mv -k`) instead of plain `mv` so history stays
  intact.
- If `git mv` is blocked by the sandbox or `.git/index.lock` is not writable, stop and leave the tracked file in
  place. Do not simulate the move with delete-plus-add; ask the user to run the `git mv` command outside the
  sandbox.

## Ruby Guidelines
- Use the project's Ruby version.
- Prefer `bundle exec` for project tools.
- Prefer binstubs when present (e.g., `bin/rspec`, `bin/rubocop`).
- Avoid early returns for simple Ruby branches when a direct conditional expression is clearer.
- Before editing, inspect:
  - `Gemfile`
  - `Gemfile.lock`
  - `*.gemspec`
  - `.rubocop.yml`
  - `.rspec`
- Run the smallest relevant test first.
- Preserve existing Ruby idioms.
- Do not add gems unless necessary.

## Project Overview

**wifi-wand** is a Ruby gem that provides cross-platform WiFi management for Mac and Ubuntu systems. 
It operates through both command-line interface and interactive shell modes, 
using OS-specific utilities under the hood while presenting a unified API.

## Development Commands

### Testing

Rake tasks select the test scope:
```bash
bundle exec rake test:safe          # default safe suite (CI-safe)
bundle exec rake test:read_only     # + real-env read-only tests
bundle exec rake test:all           # + real-env read-write tests
```

Env vars are orthogonal modifiers — combine them with any rake task or plain rspec:
```bash
WIFIWAND_VERBOSE=true bundle exec rake test:safe   # show underlying OS commands
COVERAGE_BRANCH=true bundle exec rake test:safe    # enable branch coverage analysis

# Run a specific file directly
bundle exec rspec spec/wifi-wand/models/ubuntu_model_spec.rb
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
bundle exec exe/wifi-wand shell

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
- **MacOsModel** - macOS-specific WiFi operations using `networksetup`, `system_profiler`, and optional
  Swift/CoreWLAN wrappers
- **UbuntuModel** - Ubuntu-specific operations using `nmcli`, `iw`, `ip`

### Swift/CoreWLAN Wrappers (macOS)

The macOS model uses Swift scripts with the CoreWLAN framework for improved WiFi operations:

**Location**: `lib/wifi-wand/mac_helper/swift/` directory
- `WifiNetworkConnector.swift` - Connects to WiFi networks (preferred over `networksetup`)
- `WifiNetworkDisconnector.swift` - Disconnects from networks (no sudo required)
- `AvailableWifiNetworkLister.swift` - Legacy/unused (network listing uses `system_profiler` instead)

**Fallback Strategy**:
- Swift/CoreWLAN methods are attempted first when available
- If Swift or CoreWLAN unavailable, automatically falls back to traditional utilities
- Detection happens via `swift_and_corewlan_present?` method in `mac_os_model.rb:472`
- Users can use wifi-wand without Xcode/Swift installed (reduced functionality)

**Installation**: Users can install Swift/CoreWLAN support with `xcode-select --install`

## Testing Strategy

### Test Categories
- **Safe Tests** (default): Read-only operations, safe for CI
- **Real Env Read-Only Tests**: Touch the real host environment without intentionally mutating it
- **Real Env Read-Write Tests**: Modify network state and require restoration safeguards
- **OS-Specific Tests**: Automatically filtered based on current OS

### Test Environment
- Tests automatically detect current OS and filter incompatible tests
- Network state is captured/restored for `:real_env_read_write` tests
- Use `WIFIWAND_VERBOSE=true` to debug underlying OS commands
- ResourceManager tracks and cleans up test resources

### Test Coverage
- SimpleCov generates coverage reports automatically when running tests
- HTML reports are saved to `coverage/index.html`
- Coverage is grouped by component (Models, Services, OS Detection, Core)
- Branch coverage can be enabled with `COVERAGE_BRANCH=true`
- Use the **cov-loupe** MCP tool (or CLI) to query coverage data — prefer it over reading `.resultset.json`
  directly or reasoning from scratch. For example: `cov-loupe summary lib/wifi-wand/models/mac_os_model.rb`
  or, when available, call the `file_coverage_summary` / `project_coverage` MCP tools.

### Test Refactoring Guidelines

When improving test coverage or adding new tests, follow these patterns to eliminate duplication:

#### Unified Testing Pattern for Methods with Contextual Behavior
For methods that behave differently based on context/configuration (e.g., TTY status, user permissions,
feature flags), use this unified pattern:

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
2. **Use edge case flags** for special behaviors that don't follow normal patterns (e.g., `special_case:
   false`)
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

## Git Workflow
1. **Run Tests:** Always run the test suite to verify your changes before considering them complete:
   ```bash
   bundle exec rspec
   ```
2. **Do Not Commit:** Never execute `git commit` directly. Instead, stage changes with `git add` and propose a
   clear, concise commit message for the user to use.
3. **Selective Staging:** Never assume that all uncommitted files are intended to be committed. Do not use
   `git add .` or similar catch-all commands. Explicitly stage only the files relevant to the current task.
4. **Use `--no-pager`:** When running git commands that may produce long output (e.g., `git diff`, `git log`),
   include `--no-pager` between `git` and the subcommand to prevent paging issues in automated environments:
   ```sh
   git --no-pager diff
   git --no-pager log --oneline
   ```

## Response Expectations
- Be concise and collaborative. Lead with the change/insight; follow with necessary detail.
- Reference files with inline clickable paths (e.g., `lib/wifi-wand/models/mac_os_model.rb:42`). Avoid ranges
  and external URIs.
- When providing content intended for the user to copy and paste (like commit messages or configuration
  snippets), do not include line numbers or any other decorators that would interfere with direct usage.
- Summaries use plain bullets (`-`). Offer next steps only when they flow naturally (tests, commits, builds,
  validation).
- Do not dump entire files; mention paths. Keep tone factual, note open questions, and highlight testing gaps.

## Rubocop Linting

Rubocop is used to enforce consistent code styling and best programming practices.
Write code consistent with the configured Rubocop rules, e.g. indentation.

### Markdown Line Length

Respect the Rubocop-configured line length maximum (currently 110 characters, set in `.rubocop-shared.yml`)
when writing or editing Markdown text paragraphs in this repository. Hard-wrap prose at that limit. This rule
applies only to flowing text — do not wrap code blocks, tables, list item bullets, headers, or URLs mid-token.

### Sandbox Environments

If running RuboCop in a sandboxed environment (e.g., AI coding assistants with file system restrictions), you
may encounter cache write failures:

```
Read-only file system @ rb_sysopen
  → /home/user/.cache/rubocop_cache/...
```

**Workaround:** Use the `--cache false` flag:
```sh
bundle exec rubocop --cache false
```

This disables caching and adds a few seconds to execution time but ensures successful analysis in sandboxed
environments.
