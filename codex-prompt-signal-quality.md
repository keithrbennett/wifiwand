# Codex Agent Prompt: Add WiFi Signal Quality

## Repository & Branch

Repository: `keithrbennett/wifiwand`
Branch: `claude/add-wifi-signal-strength-5PvBq`

This is a Ruby CLI tool for managing WiFi on macOS and Ubuntu. Before writing any code,
read `AGENTS.md` for project conventions.

---

## Goal

Add signal quality for the **currently connected network** to:

1. The `info` command output (new key `signal_quality` in the hash returned by `wifi_info`)
2. The `status` command output (appended to the network name in the status line)

Out of scope for this task: signal quality in the `avail_nets` / available network listing.

---

## Terminology & Units

Use the term **`signal_quality`** throughout (not `signal_strength`).

The two platforms use different native units — this is intentional and acceptable:

- **macOS**: dBm (RSSI, negative integer, e.g. `-65`). Symbol `:dbm`.
- **Ubuntu**: percentage (0–100 integer from nmcli). Symbol `:percent`.

The unit must be made explicit in all human-readable output (e.g. `-65 dBm`, `72%`).

---

## New Value Object

Create `lib/wifi_wand/signal_quality.rb`:

```ruby
# frozen_string_literal: true

module WifiWand
  SignalQuality = Struct.new(:value, :unit, keyword_init: true) do
    def to_s
      "#{value} #{unit_label}"
    end

    def unit_label
      unit == :dbm ? 'dBm' : '%'
    end
  end
end
```

---

## Architecture Overview

Platform-specific logic lives in:
- `lib/wifi_wand/platforms/mac/model.rb` — delegates heavily to extracted helper classes
- `lib/wifi_wand/platforms/ubuntu/model.rb` — monolithic, no extracted helpers

Both inherit from `lib/wifi_wand/models/base_model.rb`.

The `airport` utility has been **removed** from the codebase. Do not reference it.

---

## Changes Required

### 1. `lib/wifi_wand/signal_quality.rb` (new file)

Create the value object shown above.

---

### 2. `lib/wifi_wand/models/base_model.rb`

**a) Add abstract method declaration** (alongside the other `raise_override_not_implemented_error`
one-liners around line 234):

```ruby
def signal_quality = raise_override_not_implemented_error(__method__)
```

**b) Add to `REQUIRED_SUBCLASS_METHODS`** (the hash starting around line 143). Follow the
pattern of `bssid` — it is public and can return nil:

```ruby
signal_quality: :public,
```

**c) Add to `wifi_info`** (the hash built around line 501). Place it after the `bssid` entry
to group related network fields together:

```ruby
'signal_quality' => begin; signal_quality; rescue WifiWand::Error; nil; end,
```

**d) Add require** near the top of the file where other local requires live:

```ruby
require_relative '../signal_quality'
```

---

### 3. `lib/wifi_wand/platforms/mac/airport_data_navigator.rb`

Add a new class method after the existing `signal_strength` class method (around line 61).
This extracts the raw dBm integer for the **currently connected** network from a single
interface's data hash (i.e. the result of `AirportDataNavigator#interface_data(iface)`):

```ruby
def self.current_network_signal_dbm(interface_data)
  current_network = interface_data&.fetch(CURRENT_NETWORK_KEY, nil)
  return nil unless current_network.is_a?(Hash)

  signal_strength(current_network)
end
```

Note: `signal_strength` returns `0` as a default — treat `0` as a valid (if weak) reading;
only `nil` means "no data".

---

### 4. `lib/wifi_wand/platforms/mac/current_network_details.rb`

`CurrentNetworkDetails` already handles per-connection attributes (`connection_security_type`,
`network_hidden?`) by reading from `AirportDataNavigator`. Add `signal_quality` here.

**a) Add require** at the top (alongside the existing `require_relative 'airport_data_navigator'`):

```ruby
require_relative '../../signal_quality'
```

**b) Add the method** after `network_hidden?`:

```ruby
def signal_quality
  with_airport_data_cache_scope do
    return nil unless connected_network_name

    iface_data = airport_data_navigator.interface_data(wifi_interface)
    dbm = AirportDataNavigator.current_network_signal_dbm(iface_data)
    dbm ? SignalQuality.new(value: dbm, unit: :dbm) : nil
  end
end
```

`airport_data_navigator`, `wifi_interface`, `connected_network_name`, and
`with_airport_data_cache_scope` are already private helpers in this class.

---

### 5. `lib/wifi_wand/platforms/mac/model.rb`

**a) Add `require_relative` for signal_quality** near the top alongside the other requires:

```ruby
require_relative '../../signal_quality'
```

**b) Expose `signal_quality` as a public method** in the public section where
`connection_security_type` and `network_hidden?` are delegated (around line 507):

```ruby
public def signal_quality
  current_network_details.signal_quality
end
```

**c) Update `status_network_identity`** in `StatusQueries`
(see section 6 below — the Mac model delegates this to `StatusQueries`).

---

### 6. `lib/wifi_wand/platforms/mac/status_queries.rb`

`StatusQueries#status_network_identity` (starting around line 42) returns
`{ connected:, network_name: }`. Extend it to also return `signal_quality:`.

The method already operates inside `with_airport_data_cache_scope`. Add a private helper
that reads signal quality from airport data (which will be cache-warm in most cases since
airport data is fetched in the same scope for other purposes):

```ruby
private def current_signal_quality(deadline)
  iface_data = wifi_interface_airport_data(deadline: deadline)
  dbm = AirportDataNavigator.current_network_signal_dbm(iface_data)
  dbm ? SignalQuality.new(value: dbm, unit: :dbm) : nil
rescue WifiWand::Error
  nil
end
```

Add require at the top:

```ruby
require_relative '../../signal_quality'
```

Then update each return site in `status_network_identity` to include `signal_quality:`.

**Before** (there are three return sites — the `connected: true` early returns and the
final delegation to `status_network_identity_from_airport_data`):

```ruby
return { connected: true, network_name: helper_ssid }
...
return { connected: true, network_name: fast_network_name }
...
status_network_identity_from_airport_data(deadline)
```

**After** — for the two early returns, append the signal quality:

```ruby
return { connected: true, network_name: helper_ssid,
         signal_quality: current_signal_quality(deadline) }
...
return { connected: true, network_name: fast_network_name,
         signal_quality: current_signal_quality(deadline) }
```

For `status_network_identity_from_airport_data`, update that private method to include
`signal_quality:` in its returned hash. Airport data is already fetched there via
`wifi_interface_airport_data`, so pass it through:

```ruby
private def status_network_identity_from_airport_data(deadline)
  interface_data = wifi_interface_airport_data(deadline: deadline)
  connected = interface_associated_in_airport_data?(interface_data) ||
    status_associated_without_ssid?(deadline)
  network_name = connected ? status_network_name_from_airport_data(interface_data) : nil
  signal_quality = connected ? begin
    dbm = AirportDataNavigator.current_network_signal_dbm(interface_data)
    dbm ? SignalQuality.new(value: dbm, unit: :dbm) : nil
  end : nil

  {
    connected:      connected,
    network_name:   network_name,
    signal_quality: signal_quality,
  }
end
```

Also update `disconnected_identity` to include the key:

```ruby
private def disconnected_identity
  {
    connected:      false,
    network_name:   nil,
    signal_quality: nil,
  }
end
```

---

### 7. `lib/wifi_wand/platforms/ubuntu/model.rb`

Unlike macOS there are no extracted helper classes for Ubuntu — implement directly in
`model.rb`.

**a) Add require** near the top:

```ruby
require_relative '../../signal_quality'
```

**b) Add `signal_quality` public method.** Place it near `bssid` or `connection_security_type`
for grouping:

```ruby
public def signal_quality
  return nil unless connected?

  output = run_command(
    ['nmcli', '-t', '-f', 'IN-USE,SIGNAL', 'dev', 'wifi', 'list'],
    raise_on_error: false
  ).stdout

  output.split("\n").each do |line|
    in_use, signal = nmcli_split(line, 2)
    next unless in_use.strip == '*'

    value = signal.to_i
    return SignalQuality.new(value: value, unit: :percent)
  end

  nil
rescue WifiWand::Error
  nil
end
```

The `nmcli -t -f IN-USE,SIGNAL dev wifi list` command marks the active network with `*`
in the `IN-USE` field. `nmcli_split` is an existing private method that handles
nmcli's backslash-escaped colon delimiter.

**c) Update `status_network_identity`** (around line 111) to include `signal_quality:`:

```ruby
def status_network_identity(timeout_in_secs: nil)
  deadline = status_deadline(timeout_in_secs)
  validate_os_preconditions unless @wifi_interface
  connected = status_connected?(deadline)
  network_name = connected ? status_connected_network_name(deadline) : nil
  sq = connected ? signal_quality : nil

  {
    connected:      connected,
    network_name:   network_name,
    signal_quality: sq,
  }
end
```

---

### 8. `lib/wifi_wand/services/status_line_data_builder.rb`

`StatusLineDataBuilder` passes the network worker result through to the caller.
Update the fallback hashes so callers always get the `signal_quality` key.

In `fallback_worker_result(:network)` (around line 215):

```ruby
{
  connected:      nil,
  network_name:   nil,
  signal_quality: nil,
}
```

In `data_when_wifi_off` (around line 302):

```ruby
{
  dns_working:                   false,
  connected:                     false,
  network_name:                  nil,
  signal_quality:                nil,
  internet_state:                ConnectivityStates::INTERNET_UNREACHABLE,
  internet_check_complete:       true,
  captive_portal_state:          ConnectivityStates::CAPTIVE_PORTAL_INDETERMINATE,
  captive_portal_login_required: :unknown,
}
```

Also update `initial_data` (around line 287) so the progress snapshot has the key from
the start:

```ruby
{
  wifi_on:                       wifi_on,
  signal_quality:                nil,
  dns_working:                   nil,
  ...
}
```

---

### 9. `lib/wifi_wand/commands/output_formatter.rb`

In `status_line` (around line 75), append signal quality after the network name when
present. Find where `wifi_network_status` is assembled and add:

```ruby
signal_quality = status_data[:signal_quality]
signal_text = signal_quality ? " (#{signal_quality})" : ''
wifi_network_status = colorize_text(network_text, network_color) + signal_text
```

The `SignalQuality#to_s` format is `"-65 dBm"` or `"72%"`, so the result in the status
line would look like: `MyNetwork (-65 dBm)` or `MyNetwork (72%)`.

When network_text is `'WAIT'`, `'UNKNOWN'`, or `'[none]'` (i.e. not actually connected)
`signal_quality` will be `nil`, so `signal_text` will be `''` and nothing changes for
those cases.

---

## What NOT to Do

- Do not use the `airport` command-line utility anywhere — it has been removed.
- Do not modify `avail_nets` or the available network listing.
- Do not attempt to normalize dBm and percentage into a common unit.
- Do not add comments explaining what the code does; only add a comment if the *why*
  is non-obvious.
- Do not add error handling for scenarios that cannot happen.
- `REQUIRED_SUBCLASS_METHODS` enforces the platform contract at load time via
  `TracePoint` — adding `signal_quality: :public` there is sufficient; do not add
  duplicate runtime guards.

---

## Commit & Push

Commit all changes with a clear message and push to
`claude/add-wifi-signal-strength-5PvBq`.
