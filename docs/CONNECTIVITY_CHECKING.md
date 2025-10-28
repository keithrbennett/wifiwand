# Connectivity Checking

## Overview

The `ci` command (connectivity info) is the primary tool for checking internet connectivity. It provides a simple true/false indication of whether both DNS and TCP connectivity are working.

## Basic Usage

Check if internet is available:

```bash
wifi-wand ci
```

Output:
```
Connected to Internet: true
```

Or if not connected:
```
Connected to Internet: false
```

## Using in Scripts

The `ci` command is specifically designed for use in shell scripts where you need a simple connectivity check:

```bash
#!/bin/bash
# Check if internet is available before proceeding
if wifi-wand ci | grep -q true; then
  echo "Internet is available - proceeding with upload"
  # Do something that requires internet
  curl https://example.com/upload --data @file.txt
else
  echo "Internet is unavailable - will retry later"
  # Queue the operation for later
  exit 1
fi
```

### Exit Codes for Automation

You can also use the exit code (though the above pattern with grep is simpler):

```bash
#!/bin/bash
# Retry operation until internet is available
while ! wifi-wand ci | grep -q true; do
  echo "Waiting for internet..."
  sleep 10
done

echo "Internet is now available!"
# Proceed with network operations
```

## Comparing Connectivity Tools

| Command | Use Case | Output | Speed |
|---------|----------|--------|-------|
| `ci` | Simple connectivity check | true/false | Fast |
| `status` | Full network summary | Multi-field status | Several seconds |
| `info` | Detailed network info | Complete data | Several seconds |

Use `ci` when you just need to know "is the internet working?". Use `status` when you need the complete picture of your network state.

## Understanding the Results

`ci` checks two things:

1. **DNS Resolution**: Can the system resolve domain names?
2. **TCP Connectivity**: Can the system establish TCP connections?

Internet is considered available only when **both** are working.

## Examples

### Wait for Internet to Come Back Online

```bash
#!/bin/bash
echo "Internet went down, waiting for it to come back..."

while ! wifi-wand ci | grep -q true; do
  sleep 5
done

echo "Internet is back!"
mail -s "Internet restored" user@example.com < /dev/null
```

### Run a Task Only When Internet is Available

```bash
#!/bin/bash

if wifi-wand ci | grep -q true; then
  # Do something that requires internet
  git push origin main
  echo "Code pushed successfully"
else
  echo "No internet - skipping push"
  exit 1
fi
```

### Monitor Connectivity in a Loop

```bash
#!/bin/bash

while true; do
  if wifi-wand ci | grep -q true; then
    echo "$(date): Internet available"
  else
    echo "$(date): Internet unavailable"
  fi
  sleep 30
done
```

## Timeouts

Like the `status` command, `ci` uses intentionally long timeouts (several seconds on macOS) to avoid false positives from temporary network slowdowns. This means each check takes several seconds to complete.

If you need to check connectivity frequently, be mindful that each check will block for several seconds. Use appropriate sleep intervals between checks when polling in a loop.
