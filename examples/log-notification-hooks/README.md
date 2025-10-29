# WiFi Event Notification Hooks

Focused Ruby hooks for responding to WiFi events. Each hook does one job well.

## Quick Start

```bash
# Send events to syslog
wifi-wand log --hook ./on-wifi-event-syslog.rb

# Log events as JSON
wifi-wand log --hook ./on-wifi-event-json-log.rb

# Desktop notifications
wifi-wand log --hook ./on-wifi-event-macos-notify.rb      # macOS
wifi-wand log --hook ./on-wifi-event-gnome-notify.rb      # GNOME/Ubuntu
wifi-wand log --hook ./on-wifi-event-kde-notify.rb        # KDE Plasma

# Notify Slack
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
wifi-wand log --hook ./on-wifi-event-slack.rb

# Send to webhook
export WEBHOOK_URL="https://monitoring.example.com/events"
wifi-wand log --hook ./on-wifi-event-webhook.rb
```

## Available Hooks

### `on-wifi-event-syslog.rb`
Sends WiFi events to system syslog with appropriate severity levels.

**Usage:** `wifi-wand log --hook ./on-wifi-event-syslog.rb`

**View events:**
- macOS: `log show --predicate 'process == "wifi-wand"' --last 1h`
- Linux: `journalctl -t wifi-wand -n 20`

**Features:**
- Internet off = WARNING severity
- Internet on = NOTICE severity
- Other events = INFO severity
- Cross-platform (macOS, Linux)

### `on-wifi-event-json-log.rb`
Logs events as newline-delimited JSON (NDJSON) for parsing and analysis.

**Usage:** `wifi-wand log --hook ./on-wifi-event-json-log.rb`

**Default location:** `~/.local/share/wifi-wand/event-log.jsonl`

**Custom location:**
```bash
export WIFIWAND_JSON_LOG_FILE="/var/log/wifi-events.jsonl"
wifi-wand log --hook ./on-wifi-event-json-log.rb
```

**Analyze events:**
```bash
# Pretty-print all events
jq . ~/.local/share/wifi-wand/event-log.jsonl

# Find internet_off events
jq 'select(.type == "internet_off")' ~/.local/share/wifi-wand/event-log.jsonl

# Count events by type
jq -s 'group_by(.type) | map({type: .[0].type, count: length})' ~/.local/share/wifi-wand/event-log.jsonl
```

### `on-wifi-event-slack.rb`
Posts formatted WiFi events to Slack.

**Setup:**
1. Create Slack app at https://api.slack.com/apps
2. Enable "Incoming Webhooks"
3. Create webhook and copy URL
4. Set environment variable: `export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."`

**Usage:** `wifi-wand log --hook ./on-wifi-event-slack.rb`

**Features:**
- Color-coded messages (green/red/yellow based on event)
- Event emoji (wifi, link, globe, etc.)
- Minimal message format

### `on-wifi-event-webhook.rb`
Posts events to any HTTP endpoint as JSON.

**Setup:**
```bash
export WEBHOOK_URL="https://your-service.com/events"
wifi-wand log --hook ./on-wifi-event-webhook.rb
```

**Features:**
- Full event JSON sent as POST body
- Automatic retry on server error
- 5-second timeout with proper error handling
- Works with any HTTP service

**Testing with webhook.site:**
```bash
# Visit https://webhook.site and get your unique URL
export WEBHOOK_URL="https://webhook.site/YOUR_UNIQUE_ID"
wifi-wand log --hook ./on-wifi-event-webhook.rb
# Check webhook.site to see posted events
```

### Desktop Notifications

#### `on-wifi-event-macos-notify.rb`
Sends macOS system notifications via Notification Center using `terminal-notifier`.

**Requirements:**
- `terminal-notifier` (install via: `brew install terminal-notifier`)

**Usage:** `wifi-wand log --hook ./on-wifi-event-macos-notify.rb`

**Features:**
- Native macOS notifications via terminal-notifier
- Silently exits on non-macOS systems
- Silently exits if terminal-notifier is not installed

**Troubleshooting:**
If notifications don't appear:
1. Verify `terminal-notifier` is installed: `which terminal-notifier`
2. Test directly: `terminal-notifier -message "Test" -title "WiFi"`
3. Check macOS Notification Center settings (System Settings > Notifications)
4. Some macOS configurations may have notification delivery issues - consider using JSON logging or webhook hooks as alternatives

#### `on-wifi-event-gnome-notify.rb`
Sends GNOME/Freedesktop system notifications.

**Usage:** `wifi-wand log --hook ./on-wifi-event-gnome-notify.rb`

**Works on:**
- GNOME Desktop
- Ubuntu (with GNOME)
- Fedora (with GNOME)
- Any desktop using freedesktop.org notifications

**Features:**
- Native system notification appearance
- 5-second timeout
- Appropriate icons for each event
- No setup required
- Silently exits on non-GNOME systems

**Requirements:**
- `notify-send` command (usually pre-installed)
- D-Bus notification daemon (standard on GNOME/Ubuntu)

#### `on-wifi-event-kde-notify.rb`
Sends KDE Plasma system notifications.

**Usage:** `wifi-wand log --hook ./on-wifi-event-kde-notify.rb`

**Works on:**
- KDE Plasma 5+
- KDE Neon
- Fedora KDE Spin
- Any KDE Plasma desktop

**Features:**
- Native KDE Plasma notification style
- 5-second timeout
- Appropriate icons for each event
- No setup required
- Silently exits on non-KDE systems

**Requirements:**
- `kdialog` command (usually pre-installed)
- KDE Plasma session

## Event Structure

Each hook receives this JSON on stdin:

```json
{
  "type": "wifi_on",
  "timestamp": "2025-10-29T14:32:30.123456Z",
  "details": {
    "network_name": "HomeNetwork"
  },
  "previous_state": {
    "wifi_on": false,
    "network_name": null,
    "tcp_working": false,
    "dns_working": false,
    "internet_connected": false
  },
  "current_state": {
    "wifi_on": true,
    "network_name": null,
    "tcp_working": false,
    "dns_working": false,
    "internet_connected": false
  }
}
```

### Event Types

- `wifi_on` - WiFi radio enabled
- `wifi_off` - WiFi radio disabled
- `connected` - Joined a network (includes `network_name`)
- `disconnected` - Left a network (includes `network_name`)
- `internet_on` - Internet connectivity available
- `internet_off` - Internet connectivity lost

## Testing Hooks

Use sample events in the `sample-events/` directory:

```bash
./on-wifi-event-syslog.rb < sample-events/internet-off.json
./on-wifi-event-json-log.rb < sample-events/wifi-on.json
./on-wifi-event-slack.rb < sample-events/connected.json
```

Or use the automated test suite:

```bash
ruby test-hooks.rb              # Run all tests
ruby test-hooks.rb -v           # Verbose output
```

## Writing Custom Hooks

Create a Ruby script that reads JSON from stdin:

```ruby
#!/usr/bin/env ruby
require 'json'

event = JSON.parse($stdin.read)

case event['type']
when 'internet_off'
  # Send alert
  system('mail -s "Internet down" admin@example.com')
when 'connected'
  network = event.dig('details', 'network_name')
  puts "Connected to: #{network}"
end
```

**Requirements:**
1. Accept JSON on stdin
2. Exit with 0 on success, non-zero on failure
3. Redirect output to files (stdout is suppressed)
4. Handle errors gracefully

## Best Practices

1. **Single Purpose** - Each hook should do one thing well
2. **Error Handling** - Catch errors and log to file if needed
3. **Timeouts** - Use reasonable timeouts (5-10 seconds) for network calls
4. **Environment Variables** - Use ENV for configuration (API keys, URLs)
5. **Logging** - Log errors to `~/.local/share/wifi-wand/hook-errors.log` or similar
6. **Testing** - Test with sample events before production use
7. **Exit Codes** - Always exit with proper code (0 = success)

## Combining Multiple Hooks

### Using the Compound Hook

The easiest way to use multiple hooks is with `on-wifi-event-multi.rb`:

```bash
# Default: logs to syslog, JSON file, and native desktop notifications
wifi-wand log --hook ./on-wifi-event-multi.rb

# Add Slack alerts
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
export WIFIWAND_MULTI_SLACK=true
wifi-wand log --hook ./on-wifi-event-multi.rb

# Disable JSON logging, keep everything else
export WIFIWAND_MULTI_JSON_LOG=false
wifi-wand log --hook ./on-wifi-event-multi.rb
```

### Compound Hook Configuration

The `on-wifi-event-multi.rb` hook supports these environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `WIFIWAND_MULTI_SYSLOG` | `true` | Send events to syslog |
| `WIFIWAND_MULTI_JSON_LOG` | `true` | Log events as JSON file |
| `WIFIWAND_MULTI_NOTIFY` | `true` | Send desktop notifications (auto-detects your DE) |
| `WIFIWAND_MULTI_SLACK` | `false` | Send to Slack (requires `SLACK_WEBHOOK_URL`) |
| `WIFIWAND_MULTI_HOOK_DIR` | `.` | Directory containing hook scripts |

**Example: Log to syslog and Slack only**

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
export WIFIWAND_MULTI_SYSLOG=true
export WIFIWAND_MULTI_JSON_LOG=false
export WIFIWAND_MULTI_NOTIFY=false
export WIFIWAND_MULTI_SLACK=true
wifi-wand log --hook ./on-wifi-event-multi.rb
```

### How the Compound Hook Works

1. **Reads event JSON** from stdin (same as all hooks)
2. **Determines which hooks to run** based on configuration
3. **Auto-detects desktop environment** (macOS/GNOME/KDE) for notifications
4. **Runs each hook** sequentially, passing the event JSON via stdin
5. **Reports errors** if any hooks fail
6. **Exits with status 0** only if all configured hooks succeed

### Creating Custom Compound Hooks

You can also create your own compound hook by combining specific hooks:

```ruby
#!/usr/bin/env ruby
require 'json'

event_json = $stdin.read

# Your custom list of hooks
hooks = [
  './on-wifi-event-syslog.rb',
  './on-wifi-event-json-log.rb',
  './on-wifi-event-slack.rb'  # Only if SLACK_WEBHOOK_URL is set
]

hooks.each do |hook|
  next unless File.exist?(hook) && File.executable?(hook)

  IO.popen([hook], 'w') do |io|
    io.write(event_json)
  end

  warn "Hook failed: #{hook}" unless $?.success?
end
```

## Troubleshooting

**Hook not being called:**
- Verify hook is executable: `ls -la on-wifi-event-*.rb`
- Check hook file path is correct
- Test hook manually: `./hook.rb < sample-events/wifi-on.json`

**Hook errors:**
- Check hook exits with code 0: `echo '{}' | ./hook.rb; echo $?`
- Add logging to hook to debug
- Test with different event types

**Environment variables not working:**
- Export before running: `export VAR=value`
- Verify in hook: `echo $VAR` (in Ruby: `ENV['VAR']`)

## Security

- Never commit API keys or webhook URLs to version control
- Use `.env` files (not committed) for secrets
- Review hook source code before running
- Use HTTPS for webhooks
- Consider file permissions on log files

## License

Hook examples are provided as reference. Modify and use freely for your needs.
