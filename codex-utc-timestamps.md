# Codex Task: Add `--utc` Flag for Timestamp Timezone Control

## Goal

All user-visible wall-clock timestamps (log messages, command output lines) currently use either UTC or local time inconsistently. The goal is to make **local time the default** everywhere and add a `--utc` flag (on/off) so the user can opt into UTC output.

Monotonic clock usages (`Process.clock_gettime(Process::CLOCK_MONOTONIC)`) are for elapsed durations only and must **not** be changed.

---

## Background: How the Codebase Is Structured

- **`lib/wifi_wand/runtime_config.rb`** — Shared config object (`RuntimeConfig`) passed to all services. Currently holds `verbose`, `out_stream`, `err_stream`.
- **`lib/wifi_wand/command_line_options.rb`** — `CommandLineOptions` struct for parsed CLI flags.
- **`lib/wifi_wand/command_line_parser.rb`** — Parses global CLI flags via `OptionParser`, populates `CommandLineOptions`.
- **`lib/wifi_wand/models/base_model.rb`** — Instantiates `RuntimeConfig` (line 53) and passes it to all services (lines 58–62).
- **`lib/wifi_wand/services/event_logger.rb`** — Main timestamp-producing service. Has its own `initialize` that accepts `runtime_config:` and also individual kwargs like `verbose:`.
- **`lib/wifi_wand/services/command_executor.rb`** — Also produces a timestamp on line 177.
- **`lib/wifi_wand/commands/log.rb`** — The `log` subcommand; has its own `OptionParser` for log-specific flags and builds an `EventLogger`.

---

## Exact Changes Required

### 1. `lib/wifi_wand/runtime_config.rb`

Add a `utc` attribute alongside `verbose`:

```ruby
attr_reader :verbose, :utc

def initialize(verbose: false, utc: false, out_stream: $stdout, err_stream: $stderr)
  @verbose = !!verbose
  @utc     = !!utc
  @out_stream = out_stream
  @err_stream = err_stream
end

def utc=(value)
  @utc = !!value
end
```

Update `to_h` to include `utc: utc`.

---

### 2. `lib/wifi_wand/command_line_options.rb`

Add `:utc` to the `CommandLineOptions` struct members.

---

### 3. `lib/wifi_wand/command_line_parser.rb`

Add a global `--[no-]utc` flag in the `OptionParser` block (alongside `--verbose` etc.):

```ruby
parser.on('--[no-]utc', 'Use UTC for timestamps (default: local time)') do |value|
  options.utc = value
end
```

---

### 4. `lib/wifi_wand/models/base_model.rb`

When `RuntimeConfig` is instantiated (around line 53), pass `utc:` from the options object:

```ruby
@runtime_config = RuntimeConfig.new(
  verbose:    ...,
  utc:        options.utc || false,
  out_stream: ...,
  err_stream: ...
)
```

---

### 5. `lib/wifi_wand/services/event_logger.rb`

**5a. Constructor** — Accept a `utc:` kwarg (defaulting to reading from `runtime_config` if present, else `false`). Store it as `@utc`.

The existing pattern for `verbose` shows the right approach: there's a `runtime_config:` param and also an individual `verbose:` kwarg override. Do the same for `utc`:

```ruby
def initialize(
  model,
  interval: ...,
  log_file_path: nil,
  log_file_manager: nil,
  runtime_config: nil,
  **kwargs
)
  ...
  @runtime_config = runtime_config || RuntimeConfig.new(verbose: kwargs[:verbose], utc: kwargs[:utc])
  @utc_override = kwargs[:utc] if kwargs.key?(:utc)
  ...
end

private def utc? = defined?(@utc_override) ? @utc_override : @runtime_config.utc
```

**5b. Add a private timestamp helper:**

```ruby
private def current_timestamp(time = Time.now)
  utc? ? time.utc.iso8601 : time.localtime.iso8601
end
```

**5c. Replace all five hardcoded timestamp calls** with this helper:

| Line (approx) | Current code | Replace with |
|---|---|---|
| 89  | `Time.now.utc.iso8601` | `current_timestamp` |
| 109 | `Time.now.utc.iso8601` | `current_timestamp` |
| 148 | `Time.now.utc.iso8601` | `current_timestamp` |
| 341 | `Time.now.utc.iso8601` | `current_timestamp` |
| 426 | `event[:timestamp].utc.iso8601` | `current_timestamp(event[:timestamp])` |

Line 411 stores `Time.now` as a raw `Time` object in the event hash — leave it as `Time.now` (no timezone conversion at storage time; the conversion happens in `format_event_message` at line 426, which is already covered above).

---

### 6. `lib/wifi_wand/services/command_executor.rb`

**6a.** The `CommandExecutor` already accepts `runtime_config:` in its constructor. Confirm it stores it as `@runtime_config`.

**6b.** Add a private timestamp helper (same pattern as EventLogger):

```ruby
private def current_timestamp(time = Time.now)
  @runtime_config.utc ? time.utc.iso8601 : time.localtime.iso8601
end
```

**6c.** Replace the timestamp on line 177:

```ruby
# Before:
output.puts "#{status_string}, Duration: #{format('%.4f', duration)} seconds -- #{Time.now.iso8601}"

# After:
output.puts "#{status_string}, Duration: #{format('%.4f', duration)} seconds -- #{current_timestamp}"
```

---

### 7. `lib/wifi_wand/commands/log.rb`

The `log` subcommand has its own `OptionParser`. Add a `--[no-]utc` flag to it so users can also pass `--utc` directly to the `log` subcommand:

**7a.** In `parse_options`, add a local variable `utc_flag` defaulting to the global option if accessible, otherwise `false`:

```ruby
utc_flag = false  # or inherit from runtime_config if available
```

**7b.** In `build_parser`, add a setter lambda and option:

```ruby
private def build_parser(interval_setter:, file_setter:, stdout_setter:, verbose_setter:, utc_setter:, help_setter:)
  OptionParser.new do |opts|
    ...
    opts.on('--[no-]utc', 'Use UTC for timestamps (default: local time)') do |v|
      utc_setter.call(v)
    end
    ...
  end
end
```

Update all `build_parser` call sites (both in `help_text` and `parse_options`) to pass `utc_setter: ->(_v) {}` or `utc_setter: ->(v) { utc_flag = v }` respectively.

**7c.** Pass `utc_flag` when constructing the `EventLogger` in `build_logger`:

```ruby
WifiWand::EventLogger.new(
  model,
  interval:       interval,
  verbose:        verbose_flag,
  utc:            utc_flag,
  log_file_path:  log_file_path,
  out_stream:     logger_out_stream,
  runtime_config: model.respond_to?(:runtime_config) ? model.runtime_config : nil
)
```

---

## Default Behavior Change

- **Before:** `event_logger.rb` hardcodes `.utc`; `command_executor.rb` uses `.iso8601` without `.utc` (already local).
- **After:** Both default to **local time** unless `--utc` is passed (globally or to the `log` subcommand).

This is a intentional behavior change for `event_logger.rb` timestamps: they will now show local time by default instead of UTC.

---

## Tests to Add / Update

- `spec/wifi_wand/command_line_parser_spec.rb` — add cases for `--utc` and `--no-utc` parsing.
- `spec/wifi_wand/runtime_config_spec.rb` (if it exists) — add `utc` attribute coverage.
- `spec/wifi_wand/services/event_logger_spec.rb` — add tests verifying that with `utc: true` timestamps are UTC ISO8601, and with `utc: false` (default) they are local time ISO8601.
- `spec/wifi_wand/services/command_executor_spec.rb` — same for the verbose output line.
- `spec/wifi_wand/commands/log_spec.rb` — verify `--utc` and `--no-utc` are accepted without error.

---

## What NOT to Change

- All `Process.clock_gettime(Process::CLOCK_MONOTONIC)` calls — these measure elapsed time, not wall-clock time.
- `base_model.rb` line 527 (`'timestamp' => Time.now`) — this stores a raw `Time` object in a data hash for API consumers; timezone formatting is the consumer's responsibility.
- Ubuntu model nmcli `TIMESTAMP` field — that is an nmcli-internal integer, not a display timestamp.
- The CI status script (`latest_ci_status.rb`) — that timestamp comes from the GitHub API and is not generated by this codebase.
