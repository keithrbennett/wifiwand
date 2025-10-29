# Testing WiFi Event Notification Hooks

Guide for manually testing and validating each hook script.

## Quick Test

Test any hook with a sample event file:

```bash
./on-wifi-event-syslog.rb        < sample-events/internet-off.json
./on-wifi-event-json-log.rb      < sample-events/wifi-on.json
./on-wifi-event-macos-notify.rb  < sample-events/wifi-on.json
./on-wifi-event-gnome-notify.rb  < sample-events/connected.json
./on-wifi-event-kde-notify.rb    < sample-events/disconnected.json
./on-wifi-event-slack.rb         < sample-events/connected.json
./on-wifi-event-webhook.rb       < sample-events/connected.json
```

## Testing Each Hook

### 1. `on-wifi-event-syslog.rb` - Send to Syslog

**What it does:** Logs WiFi events to system syslog

**Test:**

```bash
./on-wifi-event-syslog.rb < sample-events/internet-off.json
```

**Verify syslog output:**

```bash
# macOS
log show --predicate 'process == "wifi-wand"' --last 10m

# Linux
journalctl -t wifi-wand -n 20
```

You should see entries like:
```
WiFi turned on
Connected to network: HomeNetwork
Internet connectivity lost
```

---

### 2. `on-wifi-event-json-log.rb` - Log as JSON

**What it does:** Appends events as NDJSON to a file

**Test:**

```bash
./on-wifi-event-json-log.rb < sample-events/wifi-on.json
./on-wifi-event-json-log.rb < sample-events/internet-on.json
./on-wifi-event-json-log.rb < sample-events/connected.json
```

**Verify file created:**

```bash
cat ~/.local/share/wifi-wand/event-log.jsonl
```

You should see three JSON objects, one per line.

**Verify JSON validity:**

```bash
jq . ~/.local/share/wifi-wand/event-log.jsonl
```

**Query events:**

```bash
# Find all internet_off events
jq 'select(.type == "internet_off")' ~/.local/share/wifi-wand/event-log.jsonl

# Get event types
jq -r '.type' ~/.local/share/wifi-wand/event-log.jsonl | sort | uniq -c
```

**Custom log location:**

```bash
export WIFIWAND_JSON_LOG_FILE="/tmp/my-events.jsonl"
./on-wifi-event-json-log.rb < sample-events/disconnected.json
cat /tmp/my-events.jsonl
```

---

### 3. `on-wifi-event-slack.rb` - Notify Slack

**Setup:**

1. Visit https://api.slack.com/apps
2. Create a new app or select existing
3. Go to "Incoming Webhooks"
4. Create a webhook or copy existing URL
5. Set environment variable: `export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../..."`

**Test:**

```bash
./on-wifi-event-slack.rb < sample-events/wifi-on.json
./on-wifi-event-slack.rb < sample-events/internet-off.json
./on-wifi-event-slack.rb < sample-events/connected.json
```

**Verify:**

Check your Slack channel for messages like:
- `:wifi: WiFi Turned On`
- `:x: Internet Unavailable`
- `:link: Connected to HomeNetwork`

**Without webhook URL:**

```bash
unset SLACK_WEBHOOK_URL
./on-wifi-event-slack.rb < sample-events/wifi-on.json
# Should print: Error: SLACK_WEBHOOK_URL environment variable not set
```

---

### 4. `on-wifi-event-webhook.rb` - Send to HTTP Endpoint

**Test with webhook.site (free service):**

1. Visit https://webhook.site
2. Copy your unique URL
3. Set environment variable: `export WEBHOOK_URL="https://webhook.site/YOUR_ID"`

**Test:**

```bash
./on-wifi-event-webhook.rb < sample-events/internet-on.json
```

**Verify:**

Go back to webhook.site and you should see the POST request with the full event JSON as the body.

**Test with local server:**

```bash
# Terminal 1: Start a test server
ruby << 'RUBY'
require 'webrick'
server = WEBrick::HTTPServer.new(
  :Port => 9999,
  :AccessLog => [],
  :Logger => WEBrick::Log.new("/dev/null")
)
server.mount_proc '/events' do |req, res|
  puts "Received #{req.method} to #{req.path}"
  puts "Body: #{req.body}"
  res.body = 'OK'
end
trap('INT') { server.shutdown }
server.start
RUBY

# Terminal 2: Send events
export WEBHOOK_URL="http://localhost:9999/events"
./on-wifi-event-webhook.rb < sample-events/wifi-off.json
```

You should see the request printed in terminal 1.

---

### 5. Desktop Notification Hooks

#### `on-wifi-event-macos-notify.rb` - macOS Notifications

**What it does:** Sends native macOS notifications via terminal-notifier

**Requirements:**
```bash
brew install terminal-notifier
```

**Test (macOS only):**

First verify terminal-notifier works:
```bash
terminal-notifier -message "Test notification" -title "WiFi"
```

If you see a notification, then test the hook:
```bash
./on-wifi-event-macos-notify.rb < sample-events/wifi-on.json
./on-wifi-event-macos-notify.rb < sample-events/internet-off.json
./on-wifi-event-macos-notify.rb < sample-events/connected.json
```

**Verify:**

Check Notification Center for messages like:
- "WiFi Turned On - WiFi is now active"
- "Internet Unavailable - Internet connection lost"
- "WiFi Connected - Connected to: HomeNetwork"

**Troubleshooting:**

If notifications don't appear:
1. Verify terminal-notifier is installed: `which terminal-notifier`
2. Test terminal-notifier directly: `terminal-notifier -message "Test" -title "WiFi"`
3. Check System Settings > Notifications for your Terminal/iTerm2 app
4. If terminal-notifier still doesn't work, use JSON logging or webhook hooks instead

**Test on non-macOS:**

```bash
# On Linux
./on-wifi-event-macos-notify.rb < sample-events/wifi-on.json
# Should exit silently with code 0
echo $?  # Should print: 0
```

---

#### `on-wifi-event-gnome-notify.rb` - GNOME Notifications

**What it does:** Sends GNOME/Freedesktop notifications (Ubuntu, Fedora, etc.)

**Requirements:**
- GNOME desktop environment
- `notify-send` command (pre-installed on most GNOME systems)

**Test:**

```bash
./on-wifi-event-gnome-notify.rb < sample-events/wifi-on.json
./on-wifi-event-gnome-notify.rb < sample-events/internet-off.json
./on-wifi-event-gnome-notify.rb < sample-events/connected.json
```

**Verify:**

Notifications should appear in the system notification area (top-right corner on most GNOME desktops) with messages like:
- "WiFi Turned On - WiFi is now active"
- "Internet Unavailable - Internet connection lost"
- "Connected - Connected to: HomeNetwork"

**Verify notify-send is available:**

```bash
which notify-send
# Should print: /usr/bin/notify-send or similar
```

**Test on non-GNOME:**

```bash
# On KDE or other non-GNOME desktop
./on-wifi-event-gnome-notify.rb < sample-events/wifi-on.json
# Should exit silently with code 0 (if notify-send available)
# Or exit with code 0 if notify-send not found
```

---

#### `on-wifi-event-kde-notify.rb` - KDE Plasma Notifications

**What it does:** Sends KDE Plasma notifications

**Requirements:**
- KDE Plasma 5+ desktop environment
- `kdialog` command (pre-installed on KDE systems)

**Test:**

```bash
./on-wifi-event-kde-notify.rb < sample-events/wifi-on.json
./on-wifi-event-kde-notify.rb < sample-events/internet-off.json
./on-wifi-event-kde-notify.rb < sample-events/connected.json
```

**Verify:**

KDE Plasma notifications should appear with messages like:
- "WiFi - WiFi is now active"
- "Internet - Internet connection lost"
- "WiFi Connected - Connected to: HomeNetwork"

Each notification should have an appropriate icon and disappear after 5 seconds.

**Verify kdialog is available:**

```bash
which kdialog
# Should print: /usr/bin/kdialog or similar
```

**Verify you're in KDE session:**

```bash
echo $KDE_FULL_SESSION
# Should print: true (or similar)
```

**Test on non-KDE:**

```bash
# On GNOME or other non-KDE desktop
./on-wifi-event-kde-notify.rb < sample-events/wifi-on.json
# Should exit silently with code 0 (KDE not detected)
```

---

### 6. `on-wifi-event-multi.rb` - Compound Hook

**What it does:** Runs multiple hooks together with configurable behavior

**Default behavior (no configuration):**
```bash
./on-wifi-event-multi.rb < sample-events/wifi-on.json
```

This will:
- ✓ Send to syslog
- ✓ Log as JSON file
- ✓ Send desktop notification (auto-detects macOS/GNOME/KDE)

**Test with different configurations:**

```bash
# Syslog and JSON only (no notifications)
export WIFIWAND_MULTI_NOTIFY=false
./on-wifi-event-multi.rb < sample-events/internet-off.json

# Syslog only
export WIFIWAND_MULTI_JSON_LOG=false
export WIFIWAND_MULTI_NOTIFY=false
./on-wifi-event-multi.rb < sample-events/connected.json

# Add Slack to the mix
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
export WIFIWAND_MULTI_SLACK=true
./on-wifi-event-multi.rb < sample-events/wifi-off.json

# Reset to defaults for next test
unset WIFIWAND_MULTI_NOTIFY
unset WIFIWAND_MULTI_JSON_LOG
unset WIFIWAND_MULTI_SLACK
unset SLACK_WEBHOOK_URL
```

**Verify results:**

Check that multiple hooks ran:
```bash
# Check syslog
log show --predicate 'process == "wifi-wand"' --last 5m   # macOS
journalctl -t wifi-wand -n 5                             # Linux

# Check JSON log
cat ~/.local/share/wifi-wand/event-log.jsonl

# Check for notifications (should have appeared)
# Check Slack (if enabled)
```

**Test hook detection:**

The compound hook auto-detects your desktop environment:
```bash
# Force a specific desktop environment for testing
export KDE_FULL_SESSION=true
./on-wifi-event-multi.rb < sample-events/wifi-on.json
# Should use KDE hook

unset KDE_FULL_SESSION
export GNOME_DESKTOP_SESSION_ID=true
./on-wifi-event-multi.rb < sample-events/wifi-on.json
# Should use GNOME hook
```

---

## Automated Testing

Use the test suite to verify all hooks:

```bash
./test-hooks.rb
./test-hooks.rb -v    # Verbose output
```

This tests:
- Hook file permissions
- JSON validity of sample events
- Hook execution with sample events
- Environment variable handling
- Error handling

---

## Testing Real Events

Once individual hooks work, test with actual WiFi events:

**Terminal 1: Start logging with a hook**

```bash
wifi-wand log --hook ./on-wifi-event-syslog.rb
```

**Terminal 2: Trigger WiFi events**

```bash
wifi-wand off
sleep 10
wifi-wand on
```

**Terminal 1: Watch events appear**

For syslog hook:
```bash
log show --predicate 'process == "wifi-wand"' --last 5m
```

---

## Debugging Hook Issues

**Hook not executing:**

```bash
# Verify it's executable
ls -la on-wifi-event-syslog.rb
# Should show rwxr-xr-x

# Test manually
./on-wifi-event-syslog.rb < sample-events/wifi-on.json
echo $?  # Should print: 0
```

**Ruby syntax error:**

```bash
ruby -c on-wifi-event-syslog.rb
# Should print: Syntax OK
```

**Missing environment variable:**

```bash
# Slack hook needs SLACK_WEBHOOK_URL
unset SLACK_WEBHOOK_URL
./on-wifi-event-slack.rb < sample-events/wifi-on.json
# Should show error and exit with non-zero code
echo $?
```

**JSON parsing error:**

```bash
# Test with invalid JSON
echo '{invalid json}' | ./on-wifi-event-syslog.rb
# Should show error and exit with code 1
```

---

## Test Coverage Checklist

- [ ] Syslog hook logs to system log
- [ ] JSON hook creates/appends to file
- [ ] Slack hook posts to webhook (if URL configured)
- [ ] Webhook hook posts to endpoint (if URL configured)
- [ ] macOS notify hook shows notifications (if on macOS)
- [ ] All hooks exit with code 0 on success
- [ ] All hooks exit with code 1 on failure
- [ ] All hooks handle missing config gracefully
- [ ] Sample events are valid JSON
- [ ] Test suite passes: `./test-hooks.rb`

---

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "command not found" | Hook not executable | `chmod +x on-wifi-event-*.rb` |
| Hook does nothing | Stdout suppressed by wifi-wand | Log to file or syslog instead |
| JSON parsing error | Invalid JSON in event | Test with sample events first |
| Slack/webhook not working | URL not set or invalid | Verify `echo $SLACK_WEBHOOK_URL` |
| Permission denied on log file | Wrong directory permissions | Create `~/.local/share/wifi-wand/` |

