# Command Architecture

_Last updated: 2026-05-16_

This document explains the current command architecture in `wifi-wand`. The date above is included so future
readers can judge whether this description may be stale.

## Purpose

The current command scheme exists to separate three concerns that used to be more entangled:

- command discovery and dispatch
- command-specific behavior
- CLI-specific support such as formatting, output, help text, and shell behavior

The goal is not to remove `CommandLineInterface` from the system. The goal is to stop putting every command's
behavior directly inside it.

## High-Level Shape

At runtime, the command system has four main layers:

1. `WifiWand::CommandLineInterface`
2. `WifiWand::Commands::Registry`
3. `WifiWand::Commands::Base` subclasses in `lib/wifi_wand/commands/`
4. `WifiWand::Commands::OutputSupport`

Very roughly:

- `CommandLineInterface` owns process-level concerns, CLI mode, streams, options, model setup, and shell
  support.
- `Registry` knows which command classes exist and resolves a command name to a bound command object.
- Each command class owns the behavior of one command.
- `OutputSupport` provides a narrower command-facing interface for output and rendering helpers.

## Main Flow

For normal command-line execution, the flow is:

1. `WifiWand::CommandLineInterface#call`
2. `WifiWand::CommandLineInterface#process_command_line`
3. `Registry#attempt_command_action`
4. `Registry#find_command_action`
5. `Registry#resolve_command`
6. `Base#bind`
7. `SomeCommandClass#call`

For shell startup, `WifiWand::Commands::Shell#call` enters interactive mode and delegates to `run_shell`.
Once the shell is running, `Commands::ShellInterface#method_missing` forwards the entered method name and
arguments into
`attempt_command_action`, so shell dispatch and command-line dispatch share the same command resolution path.

## Core Types

### `WifiWand::Commands::Metadata`

Defined in [lib/wifi_wand/commands/base.rb](../../lib/wifi_wand/commands/base.rb).

This is the small value object that holds:

- `short_string`
- `long_string`
- `description`
- `usage`

Its `aliases` method returns the short and long command names used by the registry for matching.

### `WifiWand::Commands::Base`

Defined in [lib/wifi_wand/commands/base.rb](../../lib/wifi_wand/commands/base.rb).

This is the base class for concrete command objects. It is intentionally small. Its main jobs are:

- store metadata
- define the class-level metadata declaration API
- define the class-level binding declaration API
- create a bound command instance for one CLI invocation
- provide a default help-text implementation

It no longer provides a generic fallback execution path. Real command behavior lives in command subclasses'
own `#call` methods.

### `WifiWand::Commands::Registry`

Defined in
[lib/wifi_wand/commands/registry.rb](../../lib/wifi_wand/commands/registry.rb).

This mixin is responsible for:

- constructing the list of command definitions
- finding a command by alias
- binding a command to the current CLI instance
- returning the command's callable `#call` method
- running the matched command or yielding to an error handler

The registry currently memoizes an array of command instances. It is intentionally straightforward rather than
highly abstract.

### `WifiWand::Commands::OutputSupport`

Defined in
[lib/wifi_wand/commands/output_support.rb](../../lib/wifi_wand/commands/output_support.rb).

This object exists because many commands needed only a small output-oriented slice of the CLI, not the full
`CommandLineInterface`.

It currently provides:

- `handle_output`
- `status_progress_mode`
- `strip_ansi`
- `available_networks_empty_message`
- `format_object`
- `status_line`

The CLI exposes it through `CommandLineInterface#output_support`.

## How Command Classes Are Declared

Most commands now use two class-level declarations:

### `command_metadata(...)`

Example from [info.rb](../../lib/wifi_wand/commands/info.rb):

```ruby
command_metadata(
  short_string: 'i',
  long_string:  'info',
  description:  'a hash of detailed networking information',
  usage:        'Usage: wifi-wand info'
)
```

This is the preferred declaration style for newer commands. The base class still supports the older constant
style as a fallback so older or special-case commands do not all need to migrate at once.

### `binds ...`

Example from [status.rb](../../lib/wifi_wand/commands/status.rb):

```ruby
binds :model, :interactive_mode, :out_stream, output_support: :output_support
```

This says which values a bound command instance should pull from the CLI object.

The two forms are:

- `binds :model`
  meaning "copy `cli.model` into `@model`"
- `binds output_support: :output_support`
  meaning "copy `cli.output_support` into `@output_support`"

The base class defines readers for these bound attributes automatically.

## Bound vs Unbound Command Objects

This distinction is central to the design.

An unbound command object is just the definition:

- it knows its metadata
- it knows what bindings it requires
- it may provide static help text
- it is not yet tied to a particular CLI invocation

A bound command object is created by `Base#bind(cli)`. The bound object:

- keeps the same metadata
- copies the declared execution dependencies from the CLI
- is ready to execute `#call`

This allows the registry to keep simple command definitions and then derive execution-ready instances from the
current CLI context.

## Why `CommandLineInterface` Still Exists

The command architecture did not remove the CLI object, and it was not intended to.

`CommandLineInterface` still owns:

- option parsing results
- stdout/stderr/stdin selection
- model creation
- interactive-vs-non-interactive mode
- help-system integration
- shell-mode behavior
- top-level error handling

Commands are CLI commands, not a separate general-purpose library API. For
library use, callers should prefer `WifiWand.create_model`, the concrete model
classes, and lower-level services rather than instantiating CLI command
objects.

## Why Some Commands Bind `output_support`

Many commands only need:

- a model
- maybe `interactive_mode`
- maybe streams like `out_stream`
- output/rendering behavior

For those commands, binding the full CLI object was broader than necessary.

Examples include:

- [info.rb](../../lib/wifi_wand/commands/info.rb)
- [avail_nets.rb](../../lib/wifi_wand/commands/avail_nets.rb)
- [status.rb](../../lib/wifi_wand/commands/status.rb)

These commands now depend on `output_support` for output-specific behavior and avoid reaching into unrelated
CLI helpers.

## Why Some Commands Still Bind `cli`

Not every command should be forced through `OutputSupport`.

Some commands still legitimately need the full CLI object because their behavior is about the CLI itself, not
just output:

- [help.rb](../../lib/wifi_wand/commands/help.rb)
  needs `help_text`, `resolve_command`, and `print_help`.
- [quit.rb](../../lib/wifi_wand/commands/quit.rb)
  needs shell-exit behavior through `cli.quit`.
- [till.rb](../../lib/wifi_wand/commands/till.rb)
  uses `cli.help_hint` in its validation messages.

This is intentional. The current design prefers a clear dependency over a more abstract but harder-to-read
workaround.

## Output Behavior Model

`OutputSupport#handle_output` is the main bridge between command logic and user-visible output.

Its behavior is:

- in interactive mode, return the raw data and do not print it
- in non-interactive mode with a post-processor, emit the post-processed output
- in non-interactive human-readable mode, emit the command-provided string

That is why many commands look like this:

```ruby
data = model.some_operation
output_support.handle_output(data, -> { output_support.format_object(data) })
```

This keeps the command in charge of what the human-readable string should be, while centralizing the policy
for interactive mode and machine-readable output.

## Help Text Model

There are two different help levels:

- global help from `HelpSystem#help_text`
- command-specific help from each command's `#help_text`

By default, `Base#help_text` uses metadata:

- usage line
- blank line
- description

Commands with richer help can override it. Examples:

- [help.rb](../../lib/wifi_wand/commands/help.rb)
- [log.rb](../../lib/wifi_wand/commands/log.rb)
- [till.rb](../../lib/wifi_wand/commands/till.rb)

## Shell Integration

Shell mode does not have a separate command architecture. It reuses the same one.

`Commands::ShellInterface#method_missing` passes entered names through the registry:

- if a command matches, that command runs
- otherwise a `NoMethodError` is raised with a shell-specific explanation

This means adding a new command normally makes it available both:

- on the command line
- in the interactive shell

without separate registration paths.

## How To Add a New Command

The usual steps are:

1. Create a new class in `lib/wifi_wand/commands/`.
2. Inherit from `WifiWand::Commands::Base`.
3. Declare `command_metadata(...)`.
4. Declare `binds ...` for the dependencies the command needs.
5. Implement `#call`.
6. Override `#help_text` only if the default metadata-based help is insufficient.
7. Register the command class in
   [registry.rb](../../lib/wifi_wand/commands/registry.rb).
8. Add a focused command spec under `spec/wifi_wand/commands/`.
9. Add CLI-level integration coverage only if the command needs special dispatch or shell behavior.

For simple commands, the class should stay very small. Good examples are:

- [info.rb](../../lib/wifi_wand/commands/info.rb)
- [wifi_on.rb](../../lib/wifi_wand/commands/wifi_on.rb)
- [password.rb](../../lib/wifi_wand/commands/password.rb)

## Testing Model

The command scheme is covered at several levels:

- base command behavior in
  [registry_spec.rb](../../spec/wifi_wand/commands/registry_spec.rb)
- per-command behavior in `spec/wifi_wand/commands/*`
- CLI integration behavior in the split `cli_*` spec files under
  [spec/wifi_wand/command_line_interface](../../spec/wifi_wand/command_line_interface)
- output-boundary behavior in
  [output_support_spec.rb](../../spec/wifi_wand/commands/output_support_spec.rb)

The shared example in
[spec/support/shared_command_examples.rb](../../spec/support/shared_command_examples.rb)
is especially important because it verifies that `#bind` preserves metadata and copies the expected CLI
context into the bound command.

## Current Tradeoffs

This architecture is intentionally pragmatic rather than pure.

Things it does well:

- moves command behavior out of `CommandLineInterface`
- keeps command dispatch centralized
- makes most commands easy to test in isolation
- provides a narrower output-focused boundary for many commands
- preserves a clear path for shell-mode reuse

Things it does not try to do:

- turn commands into the main library API
- eliminate `CommandLineInterface`
- build a highly abstract registry system
- force every command to avoid the full CLI object

That last point is deliberate. In this codebase, a clear direct dependency is usually better than a more
indirect abstraction that saves little real complexity.
