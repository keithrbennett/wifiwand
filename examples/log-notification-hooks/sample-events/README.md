# Sample WiFi Event JSON Files

This directory contains sample event JSON files that match the events emitted by `wifi-wand log`. 
Use these for testing and developing hooks without needing to actually trigger WiFi state changes.

## Available Sample Events

- **wifi-on.json** - WiFi radio turned on
- **wifi-off.json** - WiFi radio turned off
- **connected.json** - Connected to a network
- **disconnected.json** - Disconnected from a network
- **internet-on.json** - Internet connectivity restored
- **internet-off.json** - Internet connectivity lost

## Quick Testing

Test a hook with a sample event:

```bash
# Test syslog hook with internet-off event
./on-wifi-event-syslog.rb < sample-events/internet-off.json

# Test macOS notifications with wifi-on event
./on-wifi-event-macos-notify.rb < sample-events/wifi-on.json

# Test JSON logging with connected event
./on-wifi-event-json-log.rb < sample-events/connected.json

# Test Slack with internet-on event
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
./on-wifi-event-slack.rb < sample-events/internet-on.json
```

## Event Structure

Each sample event includes:

```json
{
  "type": "event_type",
  "timestamp": "ISO8601 timestamp",
  "details": {
    "optional": "event-specific data"
  },
  "previous_state": {
    "wifi_on": boolean,
    "network_name": "string or null",
    "tcp_working": boolean,
    "dns_working": boolean,
    "internet_connected": boolean
  },
  "current_state": {
    "same": "structure as previous_state"
  }
}
```

## Testing All Hooks

Run all hooks with different events:

```bash
for event in sample-events/*.json; do
  echo "Testing with $(basename $event)..."
  ./on-wifi-event-syslog.rb < "$event"
done
```

## Using with the Automated Test Suite

The `test-hooks.rb` script creates its own temporary events dynamically, but you can also:

1. Manually test with these samples before running automated tests
2. Modify samples to test edge cases or specific scenarios
3. Use them as templates for creating custom test events

## Creating Custom Events

You can modify these files to test different scenarios:

```bash
# Copy a sample as a template
cp sample-events/internet-off.json my-custom-event.json

# Edit it with your specific test data
nano my-custom-event.json

# Test your hook with it
./my-hook.rb < my-custom-event.json
```

## Event Timing

Sample events use realistic timestamps. You can update the `timestamp` field if you need to test time-based logic:

```bash
# Update timestamp to now
sed -i '' "s/timestamp.*/timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S)Z\",/" my-event.json
```

## Validation

Verify a sample event is valid JSON:

```bash
jq . sample-events/wifi-on.json
```

This will pretty-print the JSON and report any syntax errors.
